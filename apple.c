/*
 *  Copyright (C) 2006 Matthew Garrett
 *
 * This file is part of the ELILO, the EFI Linux boot loader.
 *
 *  ELILO is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2, or (at your option)
 *  any later version.
 *
 *  ELILO is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with ELILO; see the file COPYING.  If not, write to the Free
 *  Software Foundation, 59 Temple Place - Suite 330, Boston, MA
 *  02111-1307, USA.
 *
 * Please check out the elilo.txt for complete documentation on how
 * to use this program.
 */

#include <efi.h>
#include <efilib.h>

#include "elilo.h"
#include "graphics.h"

extern EFI_SYSTEM_TABLE *systab;
extern CHAR16 *apple_fudge_cmdline;

void *
get_protocol_handler(EFI_GUID protocol)
{
	EFI_HANDLE *handle;
	EFI_STATUS status;
	UINTN size;
	void *interface;

	status = BS->LocateHandle(ByProtocol, &protocol, NULL, &size, NULL);

	if (size==0) {
		ERR_PRT((L"Could not locate a device", status));
		return NULL;
	}

	if (size>=1000)
		size = 1000;

	handle = (EFI_HANDLE *)alloc(size, EfiLoaderData);

	if (handle == NULL) {
                ERR_PRT((L"failed to allocate handle table"));
                return NULL;
	}

 locate:
	status = BS->LocateHandle(ByProtocol, &protocol, NULL, &size, handle);

	if (status == EFI_BUFFER_TOO_SMALL) {
		handle = (EFI_HANDLE *)alloc(size, EfiLoaderData);
		goto locate;
	}

	if (status != EFI_SUCCESS) {
                ERR_PRT((L"failed to get handles: %r", status));
		ERR_PRT((L"%d",size));
                free(handle);
                return NULL;
        }

	status = BS->HandleProtocol(handle[0], &protocol, (void **)&interface);

	if (EFI_ERROR(status)) {
                ERR_PRT((L"Not able find the interface"));
		free (handle);
                return NULL;
        }

	
	
	free (handle);
	return interface;
}


EFI_STATUS
apple_fudge()
{
	EFI_GUID UGAProtocol = UGA_DRAW_PROTOCOL;
	EFI_GUID ConsoleProtocol = CONSOLE_CONTROL_PROTOCOL;
	EFI_UGA_DRAW_INTERFACE *uga_interface = 0;
	EFI_CONSOLE_CONTROL_INTERFACE *console_interface = 0;
	EFI_CONSOLE_CONTROL_SCREEN_MODE current_mode;
	UINT32 horiz, vert, depth, refresh;

	console_interface = get_protocol_handler(ConsoleProtocol);

	if (console_interface) {
		console_interface->GetMode(console_interface, &current_mode, NULL, NULL);

		if (current_mode == EfiConsoleControlScreenGraphics)
			console_interface->SetMode(console_interface, EfiConsoleControlScreenText);
			
		free (console_interface);
	} else
		ERR_PRT((L"Unable to find console interface\n"));


	uga_interface = get_protocol_handler(UGAProtocol);
	
	if (uga_interface) {
		uga_interface->GetMode(uga_interface, &horiz, &vert, &depth, &refresh);

		free (uga_interface);
	} else 
		ERR_PRT((L"Unable to find UGA interface\n"));

	apple_fudge_cmdline = alloc(76, EfiLoaderData);
	
	SPrint(apple_fudge_cmdline, 76, L"video=imacfb:height=%d,width=%d", vert, horiz);

#ifdef CONFIG_ia32
	ia32_set_legacy_free_boot(1);
#endif

	return 0;
}
	
