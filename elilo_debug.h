/*
 *  Copyright (C) 2001-2003 Hewlett-Packard Co.
 *	Contributed by Stephane Eranian <eranian@hpl.hp.com>
 *
 * This file is part of the ELILO, the EFI Linux boot loader.
 *
 *  GNU EFI is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2, or (at your option)
 *  any later version.
 *
 *  GNU EFI is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with GNU EFI; see the file COPYING.  If not, write to the Free
 *  Software Foundation, 59 Temple Place - Suite 330, Boston, MA
 *  02111-1307, USA.
 *
 * Please check out the elilo.txt for complete documentation on how
 * to use this program.
 */

#ifndef __ELILO_DEBUG__
#define __ELILO_DEBUG__

//#define DEBUG_MEM
//#define DEBUG_GZIP
//#define DEBUG_BZ

#include <efi.h>
#include <efiser.h>
#include <efierr.h>

#define  EFI_NO_MEM         EFIERR(3001)

extern CHAR16* gl_debug_buffer;
extern INTN   gl_buffer_size;
extern SERIAL_IO_INTERFACE** gl_serial_interface;
extern INTN   gl_interface_num;
extern void   serial_out_device(SERIAL_IO_INTERFACE* interface,CHAR16* pstr);

#define ELILO_DEBUG 1

#define _wrapper_print(...)                                                                 \
	do {                                                                                    \
		INTN _ii = 0;                                                                       \
		if (gl_debug_buffer != NULL) {                                                      \
			SPrint(gl_debug_buffer,gl_buffer_size, __VA_ARGS__);                            \
			Print(L"%s", gl_debug_buffer);                                                  \
		}                                                                                   \
		if (gl_serial_interface != NULL && gl_debug_buffer != NULL) {                       \
			for (_ii=0;_ii < gl_interface_num;_ii++) {                                      \
				if (gl_serial_interface[_ii] != NULL) {                                     \
					serial_out_device(gl_serial_interface[_ii], gl_debug_buffer);           \
				}                                                                           \
			}                                                                               \
		}                                                                                   \
	}while(0)

#define ERR_PRT(a)	do { _wrapper_print(L"%a(line %d):", __FILE__, __LINE__); _wrapper_print a; _wrapper_print(L"\n"); } while (0);

#ifdef ELILO_DEBUG
#define DBG_PRT(a)	do { \
		_wrapper_print(L"%a(line %d):", __FILE__, __LINE__); \
		_wrapper_print a;                                    \
		_wrapper_print(L"\n");                               \
} while (0);
#else
#define DBG_PRT(a)	do { \
	if (elilo_opt.debug) { \
		_wrapper_print(L"%a(line %d):", __FILE__, __LINE__); \
		_wrapper_print a; \
		_wrapper_print(L"\n"); \
	} \
} while (0);
#endif

EFI_STATUS init_debug_buffer(EFI_HANDLE image);
void fini_debug_buffer(void);

#endif /* __ELILO_DEBUG_H__ */
