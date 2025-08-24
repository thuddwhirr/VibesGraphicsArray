# VGA/EGA Style Video Card Specification

**Target Platform:** Gowin GW2AR-18 FPGA, programmed in Verilog

## General Architecture

The card interfaces with a 65C02 computer bus similar to a 6522 VIA chip. The CPU writes instruction codes and arguments to registers, then triggers execution. Instructions execute in the 25.175MHz video clock domain using dedicated state machines. Only one instruction executes at a time, with status available via register $000F.

### Module Architecture
- **CPU Interface**: Handles 6502 bus protocol and instruction management (1MHz domain)
- **VGA Timing Generator**: Generates 640×480@60Hz timing signals
- **Text Mode Module**: Combined text controller and renderer
- **Graphics Mode Module**: Combined graphics controller and renderer  
- **Memory Modules**: Character buffer, video memory, font ROM, and color palette
- **Top-Level Module**: Integrates all components and handles mode switching

## Features

### Text Mode (Mode 0)
- 80×30 text display with 1-line scroll buffer (31 total rows)
- 8×16 pixel font loaded from `font_8x16.mem` (binary format)
- 16-bit character format: `{attributes[15:8], char_code[7:0]}`
- Attributes: foreground[11:8], background[14:12], blink[15]
- Automatic scrolling when text exceeds bottom row

### Graphics Modes
- **Mode 1**: 640×480×2 colors, 2 pages, 1 bit/pixel (38,400 bytes/page)
- **Mode 2**: 640×480×4 colors, 1 page, 2 bits/pixel (76,800 bytes)  
- **Mode 3**: 320×240×16 colors, 2 pages, 4 bits/pixel (38,400 bytes/page)
- **Mode 4**: 320×240×64 colors, 1 page, 8 bits/pixel (76,800 bytes)

### Color System
- 6-bit RGB output (2 bits per channel)
- 16-color palette with authentic EGA-style colors:
  - 0=Black, 1=White, 2=Bright Green, 3=Dark Green, 4=Red, 5=Blue
  - 6=Yellow, 7=Magenta, 8=Cyan, 9=Dark Red, 10=Dark Blue, 11=Brown
  - 12=Gray, 13=Dark Gray, 14=Light Green, 15=Light Blue
- Mode 4 bypasses palette for direct 6-bit RGB

### Memory Model
- **Text**: 2,560×16-bit BRAM (ring buffer organization)
- **Graphics**: 76,800×8-bit BRAM (shared across all graphics modes)
- **Font**: 4,096×8-bit ROM (256 characters × 16 rows)
- **Palette**: 16×6-bit RAM (updateable color table)

## Control Interface

### Register Map ($0000-$000F)
- **$0000**: Mode control (video mode selection, active/working page)
- **$0001**: Instruction register
- **$0002-$000C**: Argument registers (function varies by instruction)
- **$000D-$000E**: Result registers (read-only)
- **$000F**: Status register (busy[0], error[1], ready[7])

## Instruction Set

### Text Instructions

#### $00 TextWrite
**Description**: Write a character to the screen at the current cursor position. Cursor position is incremented by one to the right after each write. If a write is to a cursor position below the bottom of the screen, scroll the screen up 1 row.

**Arguments**:
- `$0002`: Character properties byte (background color, foreground color, blink)
- `$0003`: Character code to write - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #$07    ; White on black attributes
STA $0002   ; Set attributes
LDA #'A'    ; Character 'A'
STA $0003   ; Write and execute
```

#### $01 TextPosition  
**Description**: Move the cursor to a new row/column, relative to the current scroll state. (row 0, col 0 is always the most upper left visible position)

**Arguments**:
- `$0002`: Row to change the cursor to (0-29)
- `$0003`: Column to change the cursor to (0-79) - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #10     ; Row 10
STA $0002   ; Set row
LDA #20     ; Column 20
STA $0003   ; Set position and execute
```

#### $02 TextClear
**Description**: Set all characters in the text buffer to null with the provided character properties.

**Arguments**:
- `$0002`: Character properties to set all values of the buffer to - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #$07    ; White on black
STA $0002   ; Clear screen and execute
```

#### $03 GetTextAt
**Description**: Get the character code and formatting data at a row and column and store it in the output registers.

**Arguments**:
- `$0002`: Row to read from (0-29)
- `$0003`: Column to read from (0-79) - **Execute instruction on update**

**Output**:
- `$000D`: Character code at provided position
- `$000E`: Formatting at provided position

**Usage Example**:
```assembly
LDA #5      ; Row 5
STA $0002   ; Set row
LDA #10     ; Column 10
STA $0003   ; Execute read
; Wait for completion...
LDA $000D   ; Get character code
LDA $000E   ; Get attributes
```

### Graphics Instructions

#### $10 WritePixel
**Description**: Write a pixel to the currently active mode and page at the pixel cursor. Increment the cursor one pixel to the right after each execution. Bitmask the provided byte appropriately for the active video mode.

**Arguments**:
- `$0002`: Color index or pixel data to write to the pixel cursor position - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #$0F    ; White pixel
STA $0002   ; Write pixel and execute
```

#### $11 PixelPos
**Description**: Set the pixel cursor position to a new X/Y.

**Arguments**:
- `$0002`: X position high-byte
- `$0003`: X position low-byte  
- `$0004`: Y position high-byte
- `$0005`: Y position low-byte - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #$01    ; X high byte (256+)
STA $0002   
LDA #$40    ; X low byte (320)
STA $0003   
LDA #$00    ; Y high byte
STA $0004   
LDA #$F0    ; Y low byte (240)
STA $0005   ; Set position and execute
```

#### $12 WritePixelPos
**Description**: Combination of WritePixel and PixelPos. Move the pixel cursor position, write data to it, and then move pixel cursor 1 to the right.

**Arguments**:
- `$0002`: X position high-byte
- `$0003`: X position low-byte
- `$0004`: Y position high-byte  
- `$0005`: Y position low-byte
- `$0006`: Color index or pixel data to write to the pixel cursor position - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #$00    ; X high byte
STA $0002   
LDA #$A0    ; X low byte (160)
STA $0003   
LDA #$00    ; Y high byte
STA $0004   
LDA #$78    ; Y low byte (120)
STA $0005   
LDA #$0C    ; Light red pixel
STA $0006   ; Set position, write pixel, and execute
```

#### $13 ClearScreen
**Description**: Clear the current active screen memory to the provided color/index.

**Arguments**:
- `$0002`: Color/color index - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #$02    ; Bright green
STA $0002   ; Clear screen and execute
```

#### $14 GetPixelAt
**Description**: Return the pixel value at the provided X/Y. Appropriately mask the output value based on mode.

**Arguments**:
- `$0002`: X position high-byte
- `$0003`: X position low-byte
- `$0004`: Y position high-byte
- `$0005`: Y position low-byte - **Execute instruction on update**

**Output**:
- `$000D`: Pixel data at the provided X/Y (1, 2, 4 or 8 bit value based on video mode)

**Usage Example**:
```assembly
LDA #$00    ; X high byte
STA $0002   
LDA #$50    ; X low byte (80)
STA $0003   
LDA #$00    ; Y high byte
STA $0004   
LDA #$60    ; Y low byte (96)
STA $0005   ; Execute read
; Wait for completion...
LDA $000D   ; Get pixel value
```

## Hardware Interface

### 6502 Bus
- 4-bit address bus
- 8-bit bidirectional data bus  
- 1MHz PHI0 clock
- R/W signal (1=read, 0=write)
- Active-low reset
- Chip enables: CE0=1, CE1B=0 for active

### VGA Output
- HSYNC, VSYNC (negative polarity)
- 6-bit RGB (2 bits each: red[1:0], green[1:0], blue[1:0])
- Standard 640×480@60Hz timing (25.175MHz pixel clock)

## Key Design Features
- Dual-port memory allows simultaneous read/write operations
- Read-modify-write logic for packed pixel modes
- Hardware scrolling via ring buffer
- Instruction-based architecture enables complex operations
- Clock domain crossing handled at CPU interface boundary
- All video operations run in fast 25.175MHz domain for smooth performance

## Programming Notes

### Status Register ($000F)
Always check the status register before issuing new instructions:
- **Bit 0 (BUSY)**: 1 = instruction executing, 0 = ready
- **Bit 1 (ERROR)**: 1 = error occurred, 0 = no error
- **Bit 7 (READY)**: 1 = ready for new instruction, 0 = busy

### Typical Instruction Sequence
```assembly
; Wait for ready
wait_ready:
    LDA $000F   ; Read status
    AND #$01    ; Check busy bit
    BNE wait_ready

; Set up instruction
LDA #$00      ; TextWrite instruction
STA $0001     ; Set instruction register
LDA #$07      ; Attributes  
STA $0002     ; Set argument 0
LDA #'H'      ; Character
STA $0003     ; Execute instruction

; Check for completion
wait_done:
    LDA $000F   ; Read status
    AND #$01    ; Check busy bit  
    BNE wait_done
```

### Mode Selection
Write to register $0000 to change video modes:
- **Bits 2:0**: Video mode (0=text, 1-4=graphics modes)
- **Bit 3**: Active page for display (modes with 2 pages)
- **Bit 4**: Working page for writes (modes with 2 pages)
- **Bit 7**: Video mode active flag (0=text, 1=graphics)

The card provides authentic 1980s graphics capabilities with modern FPGA implementation benefits.
