/*
 * Copyright (C) 1999  Internet Software Consortium.
 * 
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS" AND INTERNET SOFTWARE CONSORTIUM DISCLAIMS
 * ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL INTERNET SOFTWARE
 * CONSORTIUM BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
 * DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
 * PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
 * ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
 * SOFTWARE.
 */

/*
 * Principal Author: Bob Halley
 */

#include <config.h>

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>	/* XXX Naughty. */
#include <unistd.h>	/* XXX Naughty. */

#include <isc/assertions.h>
#include <isc/error.h>
#include <isc/boolean.h>
#include <isc/region.h>
#include <isc/list.h>
#include <isc/result.h>

#include <dns/types.h>
#include <dns/result.h>
#include <dns/name.h>
#include <dns/fixedname.h>
#include <dns/rdata.h>
#include <dns/rdataclass.h>
#include <dns/rdatatype.h>
#include <dns/rdatalist.h>
#include <dns/rdataset.h>
#include <dns/rdatasetiter.h>
#include <dns/compress.h>
#include <dns/db.h>
#include <dns/dbiterator.h>
#include <dns/dbtable.h>

#define MAXHOLD			100
#define MAXVERSIONS		100

typedef struct dbinfo {
	dns_db_t *		db;
	dns_dbversion_t *	version;
	dns_dbversion_t *	wversion;
	dns_dbversion_t *	rversions[MAXVERSIONS];
	int			rcount;
	dns_dbnode_t *		hold_nodes[MAXHOLD];
	int			hold_count;
	dns_dbiterator_t *	dbiterator;
	dns_dbversion_t *	iversion;
	int			pause_every;
	ISC_LINK(struct dbinfo)	link;
} dbinfo;

static isc_mem_t *		mctx = NULL;
static char			dbtype[128];
static dns_dbtable_t *		dbtable;
static ISC_LIST(dbinfo)		dbs;
static dbinfo *			cache_dbi = NULL;
static int			pause_every = 0;

static void
print_result(char *message, isc_result_t result) {
	size_t len;

	if (message == NULL) {
		len = 0;
		message = "";
	}
	len = strlen(message);
	printf("%s%sresult %08x: %s\n", message, (len == 0) ? "" : " ", result,
	       isc_result_totext(result));
}

static void
print_rdataset(dns_name_t *name, dns_rdataset_t *rdataset) {
	isc_buffer_t text;
	char t[1000];
	isc_result_t result;
	isc_region_t r;

	isc_buffer_init(&text, t, sizeof t, ISC_BUFFERTYPE_TEXT);
	result = dns_rdataset_totext(rdataset, name, ISC_FALSE, ISC_FALSE,
				     &text);
	isc_buffer_used(&text, &r);
	if (result == DNS_R_SUCCESS)
		printf("%.*s", (int)r.length, (char *)r.base);
	else
		print_result("", result);
}

static void
print_rdatasets(dns_name_t *name, dns_rdatasetiter_t *rdsiter) {
	isc_result_t result;
	dns_rdataset_t rdataset;

	dns_rdataset_init(&rdataset);
	result = dns_rdatasetiter_first(rdsiter);
	while (result == DNS_R_SUCCESS) {
		dns_rdatasetiter_current(rdsiter, &rdataset);
		print_rdataset(name, &rdataset);
		dns_rdataset_disassociate(&rdataset);
		result = dns_rdatasetiter_next(rdsiter);
	}
	if (result != DNS_R_NOMORE)
		print_result("", result);
}

static dbinfo *
select_db(char *origintext) {
	dns_fixedname_t forigin;
	dns_name_t *origin;
	isc_buffer_t source;
	size_t len;
	dbinfo *dbi;
	isc_result_t result;

	if (strcasecmp(origintext, "cache") == 0) {
		if (cache_dbi == NULL)
			printf("the cache does not exist\n");
		return (cache_dbi);
	}
	len = strlen(origintext);
	isc_buffer_init(&source, origintext, len, ISC_BUFFERTYPE_TEXT);
	isc_buffer_add(&source, len);
	dns_fixedname_init(&forigin);
	origin = dns_fixedname_name(&forigin);
	result = dns_name_fromtext(origin, &source, dns_rootname, ISC_FALSE,
				   NULL);
	if (result != DNS_R_SUCCESS) {
		print_result("bad name", result);
		return (NULL);
	}

	for (dbi = ISC_LIST_HEAD(dbs);
	     dbi != NULL;
	     dbi = ISC_LIST_NEXT(dbi, link)) {
		if (dns_name_compare(dns_db_origin(dbi->db), origin) == 0)
			break;
	}

	return (dbi);
}

static void
list(dbinfo *dbi) {
	dns_fixedname_t fname;
	dns_name_t *name;
	dns_dbnode_t *node;
	dns_rdatasetiter_t *rdsiter;
	isc_result_t result;
	int i;

	dns_fixedname_init(&fname);
	name = dns_fixedname_name(&fname);

	if (dbi->dbiterator == NULL) {
		INSIST(dbi->iversion == NULL);
		if (dns_db_iszone(dbi->db)) {
			if (dbi->version != NULL)
				dns_db_attachversion(dbi->db, dbi->version,
						     &dbi->iversion);
			else
				dns_db_currentversion(dbi->db, &dbi->iversion);
		}
		
		result = dns_db_createiterator(dbi->db, ISC_FALSE,
					       &dbi->dbiterator);
		if (result == DNS_R_SUCCESS)
			result = dns_dbiterator_first(dbi->dbiterator);
	} else
		result = DNS_R_SUCCESS;

	node = NULL;
	rdsiter = NULL;
	i = 0;
	while (result == DNS_R_SUCCESS) {
		result = dns_dbiterator_current(dbi->dbiterator, &node, name);
		if (result != DNS_R_SUCCESS && result != DNS_R_NEWORIGIN)
			break;
		result = dns_db_allrdatasets(dbi->db, node, dbi->iversion, 0,
					     &rdsiter);
		if (result != DNS_R_SUCCESS) {
			dns_db_detachnode(dbi->db, &node);
			break;
		}
		print_rdatasets(name, rdsiter);
		dns_rdatasetiter_destroy(&rdsiter);
		dns_db_detachnode(dbi->db, &node);
		result = dns_dbiterator_next(dbi->dbiterator);
		i++;
		if (result == DNS_R_SUCCESS && i == dbi->pause_every) {
			printf("[more...]\n");
			result = dns_dbiterator_pause(dbi->dbiterator);
			if (result == DNS_R_SUCCESS)
				return;
		}
	}
	if (result != DNS_R_NOMORE)
		print_result("", result);

	dns_dbiterator_destroy(&dbi->dbiterator);
	if (dbi->iversion != NULL)
		dns_db_closeversion(dbi->db, &dbi->iversion, ISC_FALSE);
}

static isc_result_t
load(char *filename, char *origintext, isc_boolean_t cache) {
	dns_fixedname_t forigin;
	dns_name_t *origin;
	isc_result_t result;
	isc_buffer_t source;
	size_t len;
	dbinfo *dbi;
	unsigned int i;

	dbi = isc_mem_get(mctx, sizeof *dbi);
	if (dbi == NULL)
		return (DNS_R_NOMEMORY);

	dbi->db = NULL;
	dbi->version = NULL;
	dbi->wversion = NULL;
	for (i = 0; i < MAXVERSIONS; i++)
		dbi->rversions[i] = NULL;
	dbi->hold_count = 0;
	for (i = 0; i < MAXHOLD; i++)
		dbi->hold_nodes[i] = NULL;
	dbi->dbiterator = NULL;
	dbi->iversion = NULL;
	dbi->pause_every = pause_every;
	
	len = strlen(origintext);
	isc_buffer_init(&source, origintext, len, ISC_BUFFERTYPE_TEXT);
	isc_buffer_add(&source, len);
	dns_fixedname_init(&forigin);
	origin = dns_fixedname_name(&forigin);
	result = dns_name_fromtext(origin, &source, dns_rootname, ISC_FALSE,
				   NULL);
	if (result != DNS_R_SUCCESS)
		return (result);

	result = dns_db_create(mctx, dbtype, origin, cache, dns_rdataclass_in,
			       0, NULL, &dbi->db);
	if (result != DNS_R_SUCCESS) {
		isc_mem_put(mctx, dbi, sizeof *dbi);
		return (result);
	}

	printf("loading %s (%s)\n", filename, origintext);
	result = dns_db_load(dbi->db, filename);
	if (result != DNS_R_SUCCESS) {
		dns_db_detach(&dbi->db);
		isc_mem_put(mctx, dbi, sizeof *dbi);
		return (result);
	}
	printf("loaded\n");

	if (cache) {
		INSIST(cache_dbi == NULL);
		dns_dbtable_adddefault(dbtable, dbi->db);
		cache_dbi = dbi;
	} else {
		if (dns_dbtable_add(dbtable, dbi->db) != DNS_R_SUCCESS) {
			dns_db_detach(&dbi->db);
			isc_mem_put(mctx, dbi, sizeof *dbi);
			return (result);
		}
	}
	ISC_LIST_APPEND(dbs, dbi, link);

	return (DNS_R_SUCCESS);
}

static void
unload_all(void) {
	dbinfo *dbi, *dbi_next;
	
	for (dbi = ISC_LIST_HEAD(dbs); dbi != NULL; dbi = dbi_next) {
		dbi_next = ISC_LIST_NEXT(dbi, link);
		if (dns_db_iszone(dbi->db))
			dns_dbtable_remove(dbtable, dbi->db);
		else {
			INSIST(dbi == cache_dbi);
			dns_dbtable_removedefault(dbtable);
			cache_dbi = NULL;
		}
		dns_db_detach(&dbi->db);
		ISC_LIST_UNLINK(dbs, dbi, link);
		isc_mem_put(mctx, dbi, sizeof *dbi);
	}
}

#define DBI_CHECK(dbi) \
if ((dbi) == NULL) { \
	printf("You must first select a database with !DB\n"); \
	continue; \
}
 
int
main(int argc, char *argv[]) {
	dns_db_t *db;
	dns_dbnode_t *node;
	isc_result_t result;
	dns_name_t name;
	dns_offsets_t offsets;
	size_t len;
	isc_buffer_t source, target;
	char s[1000];
	char b[255];
	dns_rdataset_t rdataset, sigrdataset;
	int ch;
	dns_rdatatype_t type = 1;
	isc_boolean_t printnode = ISC_FALSE;
	isc_boolean_t addmode = ISC_FALSE;
	isc_boolean_t delmode = ISC_FALSE;
	isc_boolean_t holdmode = ISC_FALSE;
	isc_boolean_t verbose = ISC_FALSE;
	isc_boolean_t done = ISC_FALSE;
	isc_boolean_t quiet = ISC_FALSE;
	isc_boolean_t time_lookups = ISC_FALSE;
	isc_boolean_t found_as;
	int i, v;
	dns_rdatasetiter_t *rdsiter;
	char t1[256];
	char t2[256];
	isc_buffer_t tb1, tb2;
	isc_region_t r1, r2;
	dns_fixedname_t foundname;
	dns_name_t *fname;
	unsigned int options = 0;
	struct timeval start, finish;
	char *origintext;
	dbinfo *dbi;
	dns_dbversion_t *version;
	dns_name_t *origin;
	size_t memory_quota = 0;
	dns_trust_t trust = 0;

	dns_result_register();

	RUNTIME_CHECK(isc_mem_create(0, 0, &mctx) == ISC_R_SUCCESS);
	RUNTIME_CHECK(dns_dbtable_create(mctx, dns_rdataclass_in, &dbtable) ==
		      DNS_R_SUCCESS);

	strcpy(dbtype, "rbt");
	while ((ch = getopt(argc, argv, "c:d:t:z:P:Q:gpqvT")) != -1) {
		switch (ch) {
		case 'c':
			result = load(optarg, ".", ISC_TRUE);
			if (result != DNS_R_SUCCESS)
				printf("cache load(%s) %08x: %s\n",
				       optarg, result,
				       isc_result_totext(result));
			break;
		case 'd':
			strcpy(dbtype, optarg);
			break;
		case 'g':
			options |= (DNS_DBFIND_GLUEOK|DNS_DBFIND_VALIDATEGLUE);
			break;
		case 'q':
			quiet = ISC_TRUE;
			verbose = ISC_FALSE;
			break;
		case 'p':
			printnode = ISC_TRUE;
			break;
		case 'P':
			pause_every = atoi(optarg);
			break;
		case 'Q':
			memory_quota = atoi(optarg);
			isc_mem_setquota(mctx, memory_quota);
			break;
		case 't':
			type = atoi(optarg);
			break;
		case 'T':
			time_lookups = ISC_TRUE;
			break;
		case 'v':
			verbose = ISC_TRUE;
			break;
		case 'z':
			origintext = strrchr(optarg, '/');
			if (origintext == NULL)
				origintext = optarg;
			else
				origintext++;	/* Skip '/'. */
			result = load(optarg, origintext, ISC_FALSE);
			if (result != DNS_R_SUCCESS)
				printf("zone load(%s) %08x: %s\n",
				       optarg, result,
				       isc_result_totext(result));
			break;
		}
	}

	argc -= optind;
	argv += optind;

	if (argc != 0)
		printf("ignoring trailing arguments\n");

	/*
	 * Some final initialization...
	 */
	dns_fixedname_init(&foundname);
	fname = dns_fixedname_name(&foundname);
	dbi = NULL;
	origin = dns_rootname;
	version = NULL;

	if (time_lookups) {
		/* Naughty */
		(void)gettimeofday(&start, NULL);
	}

	while (!done) {
		if (!quiet)
			printf("\n");
		if (fgets(s, sizeof s, stdin) == NULL) {
			done = ISC_TRUE;
			continue;
		}
		len = strlen(s);
		if (len > 0 && s[len - 1] == '\n') {
			s[len - 1] = '\0';
			len--;
		}
		if (verbose && dbi != NULL) {
			if (dbi->wversion != NULL)
				printf("future version (%p)\n", dbi->wversion);
			for (i = 0; i < dbi->rcount; i++)
				if (dbi->rversions[i] != NULL)
					printf("open version %d (%p)\n", i,
					       dbi->rversions[i]);
		}
		dns_name_init(&name, offsets);
		if (strcmp(s, "!R") == 0) {
			DBI_CHECK(dbi);
			if (dbi->rcount == MAXVERSIONS) {
				printf("too many open versions\n");
				continue;
			}
			dns_db_currentversion(dbi->db,
					      &dbi->rversions[dbi->rcount]);
			printf("opened version %d\n", dbi->rcount);
			dbi->version = dbi->rversions[dbi->rcount];
			version = dbi->version;
			dbi->rcount++;
			continue;
		} else if (strcmp(s, "!W") == 0) {
			DBI_CHECK(dbi);
			if (dbi->wversion != NULL) {
				printf("using existing future version\n");
				dbi->version = dbi->wversion;
				version = dbi->version;
				continue;
			}
			result = dns_db_newversion(dbi->db, &dbi->wversion);
			if (result != DNS_R_SUCCESS)
				print_result("", result);
			else
				printf("newversion\n");
			dbi->version = dbi->wversion;
			version = dbi->version;
			continue;
		} else if (strcmp(s, "!C") == 0) {
			DBI_CHECK(dbi);
			addmode = ISC_FALSE;
			delmode = ISC_FALSE;
			if (dbi->version == NULL)
				continue;
			if (dbi->version == dbi->wversion) {
				printf("closing future version\n");
				dbi->wversion = NULL;
			} else {
				for (i = 0; i < dbi->rcount; i++) {
					if (dbi->version ==
					    dbi->rversions[i]) {
						dbi->rversions[i] = NULL;
					  printf("closing open version %d\n",
						 i);
						break;
					}
				}
			}
			dns_db_closeversion(dbi->db, &dbi->version, ISC_TRUE);
			version = NULL;
			continue;
		} else if (strcmp(s, "!X") == 0) {
			DBI_CHECK(dbi);
			addmode = ISC_FALSE;
			delmode = ISC_FALSE;
			if (dbi->version == NULL)
				continue;
			if (dbi->version == dbi->wversion) {
				printf("aborting future version\n");
				dbi->wversion = NULL;
			} else {
				for (i = 0; i < dbi->rcount; i++) {
					if (dbi->version ==
					    dbi->rversions[i]) {
						dbi->rversions[i] = NULL;
					  printf("closing open version %d\n",
						 i);
						break;
					}
				}
			}
			dns_db_closeversion(dbi->db, &dbi->version, ISC_FALSE);
			version = NULL;
			continue;
		} else if (strcmp(s, "!A") == 0) {
			DBI_CHECK(dbi);
			delmode = ISC_FALSE;
			if (addmode)
				addmode = ISC_FALSE;
			else
				addmode = ISC_TRUE;
			printf("addmode = %s\n", addmode ? "TRUE" : "FALSE");
			continue;
		} else if (strcmp(s, "!D") == 0) {
			DBI_CHECK(dbi);
			addmode = ISC_FALSE;
			if (delmode)
				delmode = ISC_FALSE;
			else
				delmode = ISC_TRUE;
			printf("delmode = %s\n", delmode ? "TRUE" : "FALSE");
			continue;
		} else if (strcmp(s, "!H") == 0) {
			DBI_CHECK(dbi);
			if (holdmode)
				holdmode = ISC_FALSE;
			else
				holdmode = ISC_TRUE;
			printf("holdmode = %s\n", holdmode ? "TRUE" : "FALSE");
			continue;
		} else if (strcmp(s, "!HR") == 0) {
			DBI_CHECK(dbi);
			for (i = 0; i < dbi->hold_count; i++)
				dns_db_detachnode(dbi->db,
						  &dbi->hold_nodes[i]);
			dbi->hold_count = 0;
			holdmode = ISC_FALSE;
			printf("held nodes have been detached\n");
			continue;
		} else if (strcmp(s, "!VC") == 0) {
			DBI_CHECK(dbi);
			printf("switching to current version\n");
			dbi->version = NULL;
			version = NULL;
			continue;
		} else if (strstr(s, "!V") == s) {
			DBI_CHECK(dbi);
			v = atoi(&s[2]);
			if (v >= dbi->rcount) {
				printf("unknown open version %d\n", v);
				continue;
			} else if (dbi->rversions[v] == NULL) {
				printf("version %d is not open\n", v);
				continue;
			}
			printf("switching to open version %d\n", v);
			dbi->version = dbi->rversions[v];
			version = dbi->version;
			continue;
		} else if (strstr(s, "!TR") == s) {
			trust = (unsigned int)atoi(&s[3]);
			printf("trust level is now %u\n", (unsigned int)trust);
			continue;
		} else if (strstr(s, "!T") == s) {
			type = (unsigned int)atoi(&s[2]);
			printf("now searching for type %u\n", type);
			continue;
		} else if (strcmp(s, "!G") == 0) {
			if ((options & DNS_DBFIND_GLUEOK) != 0)
				options &= ~DNS_DBFIND_GLUEOK;
			else
				options |= DNS_DBFIND_GLUEOK;
			printf("glue ok = %s\n",
			       ((options & DNS_DBFIND_GLUEOK) != 0) ?
			       "TRUE" : "FALSE");
			continue;
		} else if (strcmp(s, "!GV") == 0) {
			if ((options & DNS_DBFIND_VALIDATEGLUE) != 0)
				options &= ~DNS_DBFIND_VALIDATEGLUE;
			else
				options |= DNS_DBFIND_VALIDATEGLUE;
			printf("validate glue = %s\n",
			       ((options & DNS_DBFIND_VALIDATEGLUE) != 0) ?
			       "TRUE" : "FALSE");
			continue;
		} else if (strcmp(s, "!WC") == 0) {
			if ((options & DNS_DBFIND_NOWILD) != 0)
				options &= ~DNS_DBFIND_NOWILD;
			else
				options |= DNS_DBFIND_NOWILD;
			printf("wildcard matching = %s\n",
			       ((options & DNS_DBFIND_NOWILD) == 0) ?
			       "TRUE" : "FALSE");
			continue;
		} else if (strcmp(s, "!LS") == 0) {
			DBI_CHECK(dbi);
			list(dbi);
			continue;
		} else if (strstr(s, "!DU ") == s) {
			DBI_CHECK(dbi);
			result = dns_db_dump(dbi->db, dbi->version, s+4);
			if (result != DNS_R_SUCCESS) {
				printf("\n");
				print_result("", result);
			}
			continue;
		} else if (strcmp(s, "!PN") == 0) {
			if (printnode)
				printnode = ISC_FALSE;
			else
				printnode = ISC_TRUE;
			printf("printnode = %s\n",
			       printnode ? "TRUE" : "FALSE");
			continue;
		} else if (strstr(s, "!P") == s) {
			DBI_CHECK(dbi);
			v = atoi(&s[2]);
			dbi->pause_every = v;
			continue;
		} else if (strcmp(s, "!DB") == 0) {
			dbi = NULL;
			origin = dns_rootname;
			version = NULL;
			printf("now searching all databases\n");
			continue;
		} else if (strncmp(s, "!DB ", 4) == 0) {
			dbi = select_db(s+4);
			if (dbi != NULL) {
				db = dbi->db;
				origin = dns_db_origin(dbi->db);
				version = dbi->version;
				addmode = ISC_FALSE;
				delmode = ISC_FALSE;
				holdmode = ISC_FALSE;
			} else {
				db = NULL;
				version = NULL;
				origin = dns_rootname;
				printf("database not found; "
				       "now searching all databases\n");
			}
			continue;
		}

		isc_buffer_init(&source, s, len, ISC_BUFFERTYPE_TEXT);
		isc_buffer_add(&source, len);
		isc_buffer_init(&target, b, sizeof b, ISC_BUFFERTYPE_BINARY);
		result = dns_name_fromtext(&name, &source, origin,
					   ISC_FALSE, &target);
		if (result != DNS_R_SUCCESS) {
			print_result("bad name: ", result);
			continue;
		}

		if (dbi == NULL) {
			db = NULL;
			result = dns_dbtable_find(dbtable, &name, &db);
			if (result != DNS_R_SUCCESS &&
			    result != DNS_R_PARTIALMATCH) {
				if (!quiet) {
					printf("\n");
					print_result("", result);
				}
				continue;
			}
			isc_buffer_init(&tb1, t1, sizeof t1,
					ISC_BUFFERTYPE_TEXT);
			result = dns_name_totext(dns_db_origin(db), ISC_FALSE,
						 &tb1);
			if (result != DNS_R_SUCCESS) {
				printf("\n");
				print_result("", result);
				dns_db_detach(&db);
				continue;
			}
			isc_buffer_used(&tb1, &r1);
			printf("\ndatabase = %.*s (%s)\n",
			       (int)r1.length, r1.base,
			       (dns_db_iszone(db)) ? "zone" : "cache");
		}
		node = NULL;
		dns_rdataset_init(&rdataset);
		dns_rdataset_init(&sigrdataset);
		result = dns_db_find(db, &name, version, type, options, 0,
				     &node, fname, &rdataset, &sigrdataset);
		if (!quiet) {
			if (dbi != NULL)
				printf("\n");
			print_result("", result);
		}

		found_as = ISC_FALSE;
		switch (result) {
		case DNS_R_SUCCESS:
		case DNS_R_GLUE:
		case DNS_R_CNAME:
		case DNS_R_ZONECUT:
			break;
		case DNS_R_DNAME:
		case DNS_R_DELEGATION:
			found_as = ISC_TRUE;
			break;
		case DNS_R_NXRDATASET:
			if (dns_rdataset_isassociated(&rdataset))
				break;
			if (dbi != NULL) {
				if (holdmode) {
					RUNTIME_CHECK(dbi->hold_count <
						      MAXHOLD);
					dbi->hold_nodes[dbi->hold_count++] =
						node;
					node = NULL;
				} else
					dns_db_detachnode(db, &node);
			} else {
				dns_db_detachnode(db, &node);
				dns_db_detach(&db);
			}
			continue;
		case DNS_R_NXDOMAIN:
			if (dns_rdataset_isassociated(&rdataset))
				break;
			/* FALLTHROUGH */
		default:
			if (dbi == NULL)
				dns_db_detach(&db);
			if (quiet)
				print_result("", result);
			continue;
		}
		if (found_as && !quiet) {
			isc_buffer_init(&tb1, t1, sizeof t1,
					ISC_BUFFERTYPE_TEXT);
			isc_buffer_init(&tb2, t2, sizeof t2,
					ISC_BUFFERTYPE_TEXT);
			result = dns_name_totext(&name, ISC_FALSE, &tb1);
			if (result != DNS_R_SUCCESS) {
				print_result("", result);
				dns_db_detachnode(db, &node);
				if (dbi == NULL)
					dns_db_detach(&db);
				continue;
			}
			result = dns_name_totext(fname, ISC_FALSE, &tb2);
			if (result != DNS_R_SUCCESS) {
				print_result("", result);
				dns_db_detachnode(db, &node);
				if (dbi == NULL)
					dns_db_detach(&db);
				continue;
			}
			isc_buffer_used(&tb1, &r1);
			isc_buffer_used(&tb2, &r2);
			printf("found %.*s as %.*s\n",
			       (int)r1.length, r1.base,
			       (int)r2.length, r2.base);
		}

		if (printnode)
			dns_db_printnode(db, node, stdout);

		if (!found_as && type == dns_rdatatype_any) {
			rdsiter = NULL;
			result = dns_db_allrdatasets(db, node, version, 0,
						     &rdsiter);
			if (result == DNS_R_SUCCESS) {
				if (!quiet)
					print_rdatasets(fname, rdsiter);
				dns_rdatasetiter_destroy(&rdsiter);
			} else
				print_result("", result);
		} else {
			if (!quiet)
				print_rdataset(fname, &rdataset);
			if (dns_rdataset_isassociated(&sigrdataset)) {
				if (!quiet)
					print_rdataset(fname, &sigrdataset);
				dns_rdataset_disassociate(&sigrdataset);
			}
			if (dbi != NULL && addmode && !found_as) {
				rdataset.ttl++;
				rdataset.trust = trust;
				result = dns_db_addrdataset(db, node, version,
							    0, &rdataset,
							    dns_db_iszone(db),
							    NULL);
				if (result != DNS_R_SUCCESS)
					print_result("", result);
				if (printnode)
					dns_db_printnode(db, node, stdout);
			} else if (dbi != NULL && delmode && !found_as) {
				result = dns_db_deleterdataset(db, node,
							       version, type);
				if (result != DNS_R_SUCCESS)
					print_result("", result);
				if (printnode)
					dns_db_printnode(db, node, stdout);
			}
			dns_rdataset_disassociate(&rdataset);
		}

		if (dbi != NULL) {
			if (holdmode) {
				RUNTIME_CHECK(dbi->hold_count < MAXHOLD);
				dbi->hold_nodes[dbi->hold_count++] = node;
				node = NULL;
			} else
				dns_db_detachnode(db, &node);
		} else {
			dns_db_detachnode(db, &node);
			dns_db_detach(&db);
		}
	}

	if (time_lookups) {
		struct timeval interval;

		/* Naughty */
		(void)gettimeofday(&finish, NULL);
		if (start.tv_usec > finish.tv_usec) {
			finish.tv_sec--;
			interval.tv_usec = 1000000 -
				start.tv_usec + finish.tv_usec;
		} else
			interval.tv_usec = finish.tv_usec - start.tv_usec;
		interval.tv_sec = finish.tv_sec - start.tv_sec;
		printf("elapsed time: %lu.%06lu seconds\n",
		       (unsigned long)interval.tv_sec,
		       (unsigned long)interval.tv_usec);
	}

	unload_all();

	dns_dbtable_detach(&dbtable);

	if (!quiet)
		isc_mem_stats(mctx, stdout);

	return (0);
}
