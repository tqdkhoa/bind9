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

/* $Id: dir.h,v 1.2 1999/10/01 01:12:04 tale Exp $ */

/* Principal Authors: DCL */

#ifndef DIRENT_H
#define DIRENT_H 1

#include <sys/types.h>
#include <dirent.h>
#include <limits.h>

#include <isc/lang.h>
#include <isc/result.h>

ISC_LANG_BEGINDECLS

typedef struct {
	/*
	 * Ideally, this should be NAME_MAX, but AIX does not define it by
	 * default and dynamically allocating the space based on pathconf()
	 * complicates things undesirably, as does adding special conditionals
	 * just for AIX.  So a comfortably sized buffer is chosen instead.
	 */
	char 		name[256];
	unsigned int	length;
} isc_direntry_t;

typedef struct {
	int		magic;
	/*
	 * As with isc_direntry_t->name, making this "right" for all systems
	 * is slightly problematic because AIX does not define PATH_MAX.
	 */
	char		dirname[1024];
	isc_direntry_t	entry;
	DIR *		handle;
} isc_dir_t;

void
isc_dir_init(isc_dir_t *dir);

isc_result_t
isc_dir_open(const char *dirname, isc_dir_t *dir);

isc_result_t
isc_dir_read(isc_dir_t *dir);

isc_result_t
isc_dir_reset(isc_dir_t *dir);

void
isc_dir_close(isc_dir_t *dir);

ISC_LANG_BEGINDECLS

#endif /* DIRENT_H */
