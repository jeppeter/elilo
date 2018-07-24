#ifndef UGA_H
#define UGA_H

#define UGA_DRAW_PROTOCOL \
{ 0x982c298b,0xf4fa,0x41cb,{ 0xb8,0x38,0x77,0xaa,0x68,0x8f,0xb8,0x39 } }

struct _EFI_UGA_DRAW_INTERFACE;

typedef
EFI_STATUS
(EFIAPI *EFI_UGA_DRAW_PROTOCOL_GET_MODE) (
	IN struct _EFI_UGA_DRAW_INTERFACE	*This,
	OUT UINT32 	*HorizontalResolution,
	OUT UINT32	*VerticalResolution,
	OUT UINT32	*ColorDepth,
	OUT UINT32      *RefreshRate
	);

typedef
EFI_STATUS
(EFIAPI *EFI_UGA_DRAW_PROTOCOL_SET_MODE) (
	IN struct _EFI_UGA_DRAW_INTERFACE *This,
	IN UINT32	HorizontalResolution,
	IN UINT32	VerticalResolution,
	IN UINT32	ColorDepth,
	IN UINT32       RefreshRate
	);

typedef struct {
	UINT8   Blue;
	UINT8   Green;
	UINT8   Red;
	UINT8   Reserved;
} EFI_UGA_PIXEL;
typedef enum {
	EfiUgaVideoFill,
	EfiUgaVideoToBltBuffer,
	EfiUgaBltBufferToVideo,
	EfiUgaVideoToVideo,
	EfiUgaBltMax
} EFI_UGA_BLT_OPERATION;

typedef
EFI_STATUS
(EFIAPI *EFI_UGA_DRAW_PROTOCOL_BLT) (
	IN struct _EFI_UGA_DRAW_INTERFACE	*This,
	IN OUT EFI_UGA_PIXEL	*BltBuffer,
	IN EFI_UGA_BLT_OPERATION	BltOperation,
	IN UINTN	SourceX,
	IN UINTN	SourceY,
	IN UINTN	DestinationX,
	IN UINTN	DestinationY,
	IN UINTN	Width,
	IN UINTN	Height,
	IN UINTN      Delta 
	);

typedef struct _EFI_UGA_DRAW_INTERFACE {
	EFI_UGA_DRAW_PROTOCOL_GET_MODE GetMode;
	EFI_UGA_DRAW_PROTOCOL_SET_MODE SetMode;
	EFI_UGA_DRAW_PROTOCOL_BLT Blt;
} EFI_UGA_DRAW_INTERFACE;

/* Console control */

#define CONSOLE_CONTROL_PROTOCOL \
  { 0xf42f7782, 0x12e, 0x4c12,{ 0x99, 0x56, 0x49, 0xf9, 0x43, 0x4, 0xf7, 0x21} }

struct _EFI_CONSOLE_CONTROL_INTERFACE;

typedef enum {
	EfiConsoleControlScreenText,
	EfiConsoleControlScreenGraphics,
	EfiConsoleControlScreenMaxValue
} EFI_CONSOLE_CONTROL_SCREEN_MODE;

typedef
EFI_STATUS
(EFIAPI *EFI_CONSOLE_CONTROL_PROTOCOL_GET_MODE) (
	IN  struct _EFI_CONSOLE_CONTROL_INTERFACE      *This,
	OUT EFI_CONSOLE_CONTROL_SCREEN_MODE   *Mode,
	OUT BOOLEAN                           *UgaExists,
	OUT BOOLEAN                           *StdInLocked
	);

typedef
EFI_STATUS
(EFIAPI *EFI_CONSOLE_CONTROL_PROTOCOL_SET_MODE) (
	IN  struct _EFI_CONSOLE_CONTROL_INTERFACE      *This,
	OUT EFI_CONSOLE_CONTROL_SCREEN_MODE   Mode
	);

typedef
EFI_STATUS
(EFIAPI *EFI_CONSOLE_CONTROL_PROTOCOL_LOCK_STD_IN) (
	IN  struct _EFI_CONSOLE_CONTROL_INTERFACE      *This,
	IN CHAR16                             *Password
	);

typedef struct _EFI_CONSOLE_CONTROL_INTERFACE {
	EFI_CONSOLE_CONTROL_PROTOCOL_GET_MODE           GetMode;
	EFI_CONSOLE_CONTROL_PROTOCOL_SET_MODE           SetMode;
	EFI_CONSOLE_CONTROL_PROTOCOL_LOCK_STD_IN        LockStdIn;
} EFI_CONSOLE_CONTROL_INTERFACE;


#endif /* UGA_H */
