/*
 * Copyright (C) 1999-2002  Internet Software Consortium.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND INTERNET SOFTWARE CONSORTIUM
 * DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL
 * INTERNET SOFTWARE CONSORTIUM BE LIABLE FOR ANY SPECIAL, DIRECT,
 * INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING
 * FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
 * NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
 * WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

/* $Id: masterdump.h,v 1.27 2002/02/20 03:34:31 marka Exp $ */

#ifndef DNS_MASTERDUMP_H
#define DNS_MASTERDUMP_H 1

/***
 ***	Imports
 ***/

#include <stdio.h>

#include <isc/lang.h>

#include <dns/types.h>

/***
 *** Types
 ***/

/*
 * Style options for masterfile dumps.  This struct is currently
 * opaque, so applications cannot define their own style but have
 * to choose a predefined style.  A more flexible interface may
 * be exported in the future.
 */

typedef struct dns_master_style dns_master_style_t;

ISC_LANG_BEGINDECLS

/***
 ***	Constants
 ***/

/*
 * The default master file style.
 *
 * This uses $TTL directives to avoid the need to dedicate a
 * tab stop for the TTL.  The class is only printed for the first
 * rrset in the file and shares a tab stop with the RR type.
 */
LIBDNS_EXTERNAL_DATA extern const dns_master_style_t dns_master_style_default;

/*
 * A master file style that prints explicit TTL values on each 
 * record line, never using $TTL statements.  The TTL has a tab 
 * stop of its own, but the class and type share one.
 */
LIBDNS_EXTERNAL_DATA extern const dns_master_style_t
				  dns_master_style_explicitttl;

/*
 * A master style format designed for cache files.  It prints explicit TTL
 * values on each record line and never uses $ORIGIN or relative names.
 */
LIBDNS_EXTERNAL_DATA extern const dns_master_style_t dns_master_style_cache;

/*
 * A master style that prints name, ttl, class, type, and value on 
 * every line.  Similar to explicitttl above, but more verbose.  
 * Intended for generating master files which can be easily parsed 
 * by perl scripts and similar applications.
 */
LIBDNS_EXTERNAL_DATA extern const dns_master_style_t dns_master_style_simple;

/*
 * The style used for debugging, "dig" output, etc.
 */
LIBDNS_EXTERNAL_DATA extern const dns_master_style_t dns_master_style_debug;

/***
 ***	Functions
 ***/

void
dns_dumpctx_attach(dns_dumpctx_t *source, dns_dumpctx_t **target);
/*
 * Attach to a dump context.
 *
 * Require:
 *	'source' to be valid.
 *	'target' to be non NULL and '*target' to be NULL.
 */

void
dns_dumpctx_detach(dns_dumpctx_t **dctxp);
/*
 * Detach from a dump context.
 *
 * Require:
 *	'dctxp' to point to a valid dump context.
 *
 * Ensures:
 *	'*dctxp' is NULL.
 */

void
dns_dumpctx_cancel(dns_dumpctx_t *dctx);
/*
 * Cancel a in progress dump.
 *
 * Require:
 *	'dctx' to be valid.
 */

dns_dbversion_t *
dns_dumpctx_version(dns_dumpctx_t *dctx);
/*
 * Return the version handle (if any) of the database being dumped.
 *
 * Require:
 *	'dctx' to be valid.
 */

dns_db_t *
dns_dumpctx_db(dns_dumpctx_t *dctx);
/*
 * Return the database being dumped.
 *
 * Require:
 *	'dctx' to be valid.
 */


isc_result_t
dns_master_dumptostreaminc(isc_mem_t *mctx, dns_db_t *db,
			   dns_dbversion_t *version,
			   const dns_master_style_t *style, FILE *f,
			   isc_task_t *task, dns_dumpdonefunc_t done,
			   void *done_arg, dns_dumpctx_t **dctxp);

isc_result_t
dns_master_dumptostream(isc_mem_t *mctx, dns_db_t *db,
			dns_dbversion_t *version,
			const dns_master_style_t *style, FILE *f);
/*
 * Dump the database 'db' to the steam 'f' in RFC1035 master
 * file format, in the style defined by 'style'
 * (e.g., &dns_default_master_style_default)
 *
 * Temporary dynamic memory may be allocated from 'mctx'.
 *
 * Require:
 *	'task' to be valid.
 *	'done' to be non NULL.
 *	'dctxp' to be non NULL && '*dctxp' to be NULL.
 * 
 * Returns:
 *	ISC_R_SUCCESS
 *	ISC_R_CONTINUE	dns_master_dumptostreaminc() only.
 *	ISC_R_NOMEMORY
 * 	Any database or rrset iterator error.
 *	Any dns_rdata_totext() error code.
 */

isc_result_t
dns_master_dumpinc(isc_mem_t *mctx, dns_db_t *db, dns_dbversion_t *version,
		   const dns_master_style_t *style, const char *filename,
		   isc_task_t *task, dns_dumpdonefunc_t done, void *done_arg,
		   dns_dumpctx_t **dctxp);

isc_result_t
dns_master_dump(isc_mem_t *mctx, dns_db_t *db,
		dns_dbversion_t *version,
		const dns_master_style_t *style, const char *filename);
/*
 * Dump the database 'db' to the file 'filename' in RFC1035 master
 * file format, in the style defined by 'style'
 * (e.g., &dns_default_master_style_default)
 *
 * Temporary dynamic memory may be allocated from 'mctx'.
 *
 * Returns:
 *	ISC_R_SUCCESS
 *	ISC_R_CONTINUE	dns_master_dumpinc() only.
 *	ISC_R_NOMEMORY
 * 	Any database or rrset iterator error.
 *	Any dns_rdata_totext() error code.
 */

isc_result_t
dns_master_rdatasettotext(dns_name_t *owner_name,
			  dns_rdataset_t *rdataset,
			  const dns_master_style_t *style,
			  isc_buffer_t *target);
/*
 * Convert 'rdataset' to text format, storing the result in 'target'.
 *
 * Notes:
 *	The rdata cursor position will be changed.
 *
 * Requires:
 *	'rdataset' is a valid non-question rdataset.
 *
 *	'rdataset' is not empty.
 */

isc_result_t
dns_master_questiontotext(dns_name_t *owner_name,
			  dns_rdataset_t *rdataset,
			  const dns_master_style_t *style,
			  isc_buffer_t *target);

isc_result_t
dns_master_dumpnodetostream(isc_mem_t *mctx, dns_db_t *db,
			    dns_dbversion_t *version,
			    dns_dbnode_t *node, dns_name_t *name,
			    const dns_master_style_t *style,
			    FILE *f);

isc_result_t
dns_master_dumpnode(isc_mem_t *mctx, dns_db_t *db, dns_dbversion_t *version,
		    dns_dbnode_t *node, dns_name_t *name,
		    const dns_master_style_t *style, const char *filename);

ISC_LANG_ENDDECLS

#endif /* DNS_MASTERDUMP_H */
