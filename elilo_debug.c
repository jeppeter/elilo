#include "elilo_debug.h"
#include <efilib.h>

CHAR16* gl_debug_buffer = NULL;
INTN  gl_debug_num = 2048;
INTN  gl_debug_size = 0;
INTN  gl_interface_num = 0;
SERIAL_IO_INTERFACE** gl_serial_interface = NULL;

static EFI_GUID st_efi_serial_io_guid = SERIAL_IO_PROTOCOL;

static int __get_serial_control_handler(EFI_HANDLE** pphandles, UINTN* psize)
{
    int num = 0;
    EFI_STATUS status;
    EFI_HANDLE *prethandle = NULL;
    UINTN retsize = 0;
    int ret = 0;

    if (pphandles == NULL || psize == NULL) {
        return (int)EFI_INVALID_PARAMETER;
    }
    prethandle = *pphandles;
    retsize = *psize;

try_again:
    status = uefi_call_wrapper(BS->LocateHandle, 5, ByProtocol, &st_efi_serial_io_guid, 0, &retsize, &prethandle);
    if (status != EFI_SUCCESS) {
        if (status != EFI_BUFFER_TOO_SMALL) {
            ret = status;
            goto fail;
        }

        if (prethandle != NULL && prethandle != *pphandles) {
            free(prethandle);
        }
        prethandle = NULL;
        Print(L"retsize %d\n",retsize);
        prethandle = alloc(retsize, EfiBootServicesData);
        if (prethandle == NULL) {
        	status = EFI_NO_MEM;
            goto fail;
        }
        goto try_again;
    }

    if (*pphandles != NULL && *pphandles != prethandle) {
        free(*pphandles);
    }
    *pphandles = prethandle;
    *psize = retsize;
    num = retsize / sizeof(*pphandles);

    return num;
fail:
    if (prethandle != NULL && prethandle != *pphandles) {
        free(prethandle);
    }
    prethandle = NULL;
    retsize = 0;
    return ret;
}

static EFI_STATUS init_config(SERIAL_IO_INTERFACE* interface)
{
    EFI_STATUS status;
    status = uefi_call_wrapper(interface->Reset, 1, interface);
    if (status != EFI_SUCCESS) {
        return status;
    }
    status = uefi_call_wrapper(interface->SetAttributes, 7, interface, 0,
                               0, 0, DefaultParity,
                               0,
                               DefaultStopBits);
    if (status != EFI_SUCCESS) {
        return status;
    }
    return EFI_SUCCESS;
}


static EFI_STATUS __get_serial_interface(EFI_HANDLE image)
{
    EFI_HANDLE *handles = NULL,*handle=NULL;

    UINTN handlesize = 0;
    int handlenum = 0;
    int i;
    EFI_STATUS status;
    if (gl_serial_interface != NULL) {
        return EFI_SUCCESS;
    }
    handlenum = __get_serial_control_handler(&handles, &handlesize);
    if (handlenum < 0) {
        status = handlenum;
        goto fail;
    }
    gl_interface_num = handlenum;
    status = uefi_call_wrapper(BS->AllocatePool, 3, EfiBootServicesData, gl_interface_num * sizeof(gl_serial_interface[0]), &gl_serial_interface);
    if (status != EFI_SUCCESS) {
        goto fail;
    }

    for (i = 0; i < handlenum; i++) {
        gl_serial_interface[i] = NULL;
    }
    Print(L"num handles %d\n", handlenum);

    for (i = 0, handle = handles; i < handlenum; i++, handle ++) {
        status = uefi_call_wrapper(BS->OpenProtocol, 6, handle, &st_efi_serial_io_guid,
                                   &(gl_serial_interface[i]), image, 0, EFI_OPEN_PROTOCOL_GET_PROTOCOL);
        if (status != EFI_SUCCESS) {
            gl_serial_interface[i] = NULL;
            Print(L"[%d] [0x%llx] OpenProtocol error [%lld:0x%llx]\n", i, handles[i], status, status);
        } else {
            status = init_config(gl_serial_interface[i]);
            if (status != EFI_SUCCESS) {
                gl_serial_interface[i] = NULL;
                Print(L"init [%d] failed\n", i);
            } else {
                Print(L"init [%d] succ\n", i );
            }
        }
    }

    if (handles != NULL) {
        uefi_call_wrapper(BS->FreePool, 1, handles);
    }
    handles = NULL;
    handlesize = 0;
    handlenum = 0;
    return EFI_SUCCESS;
fail:
    if (handles != NULL) {
        uefi_call_wrapper(BS->FreePool, 1, handles);
    }
    handles = NULL;
    handlesize = 0;
    handlenum = 0;
    return status;

}



EFI_STATUS init_debug_buffer(EFI_HANDLE image)
{
    EFI_STATUS ret ;

    Print(L"Init Buffer\n");
    if (gl_debug_buffer == NULL) {
        gl_debug_size = gl_debug_num * sizeof(CHAR16);
        gl_debug_buffer = alloc(gl_debug_size, EfiBootServicesData);
        if (gl_debug_buffer == NULL) {
        	ret = EFI_NO_MEM;
            goto fail;
        }
    }

    Print(L"Init interface\n");
    ret = __get_serial_interface(image);
    if (ret != EFI_SUCCESS) {
        Print(L"can not find serial protocol %d\n", ret);
        goto fail;
    }

    return EFI_SUCCESS;

fail:
    gl_serial_interface = NULL;
    if (gl_debug_buffer != NULL) {
    	free(gl_debug_buffer);
    }
    gl_debug_buffer = NULL;
    return ret;
}

void fini_debug_buffer(void)
{
    gl_serial_interface = NULL;
    gl_interface_num = 0;
    if (gl_debug_buffer != NULL) {
    	free(gl_debug_buffer);
    }
    gl_debug_buffer = NULL;
    return;
}

void   serial_out_device(SERIAL_IO_INTERFACE* interface,CHAR16* pstr)
{
	char curch;
	INTN i;
	INTN bufsize=1;

	for (i=0;pstr[i]!= 0x00;i++) {
		bufsize = 1;
		curch = (char) pstr[i] & 0xff;
		uefi_call_wrapper(interface->Write,3, interface, &bufsize,&curch);
	}
	return ;

}