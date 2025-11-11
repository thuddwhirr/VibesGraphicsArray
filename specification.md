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
- **Hardware cursor**: Block cursor using character's foreground color
  - Position controlled by TEXT_POSITION instruction
  - Enable/blink controlled by mode control register bits 5-6

### Graphics Modes
- **Mode 1**: 640×480×2 colors, 2 pages, 1 bit/pixel (38,400 bytes/page)
- **Mode 2**: 640×480×4 colors, 1 page, 2 bits/pixel (76,800 bytes)
- **Mode 3**: 320×240×16 colors, 2 pages, 4 bits/pixel (38,400 bytes/page)
- **Mode 4**: 320×240×256 colors, 1 page, 8 bits/pixel (76,800 bytes)

### Color System
- 12-bit RGB output (4 bits per channel) via external DAC
- **16-color fixed palette** (Modes 1-3) with authentic EGA-style colors:
  - 0=Black, 1=White, 2=Bright Green, 3=Dark Green, 4=Red, 5=Blue
  - 6=Yellow, 7=Magenta, 8=Cyan, 9=Dark Red, 10=Dark Blue, 11=Brown
  - 12=Gray, 13=Dark Gray, 14=Light Green, 15=Light Blue
- **256-color writable palette** (Mode 4):
  - Programmable via SET_PALETTE_ENTRY instruction ($20)
  - 12-bit RGB per entry (4096 color gamut)
  - Enables palette effects: color cycling, fades, screen flashes

### Memory Model
- **Text**: 2,560×16-bit BRAM (ring buffer organization)
- **Graphics**: 76,800×8-bit BRAM (shared across all graphics modes)
- **Font**: 4,096×8-bit ROM (256 characters × 16 rows)
- **Fixed Palette**: 16×12-bit RAM (Modes 1-3, currently read-only)
- **Writable Palette**: 256×12-bit distributed RAM (Mode 4, programmable)

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

#### $04 TextCommand
**Description**: Process non-glyph ASCII command codes.
- `$08`: backspace. move cursor back one character and set character in the new position to space ($20).

- `$09`: tab. advance cursor 8 increments.
- `$0A`: line feed. move cursor to col 0 of next row. Scroll if next row is past threshold.
- `$0D`: carrige return. move cursor to col 0 of current row.
- `$7F`: delete. set char at current cursor postion to space ($20). do not advance cursor. 

**Arguments**: 
- `$0002`: Command code. - **Execute instruction on update **

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

### Palette Instructions (Mode 4 only)

#### $20 SetPaletteEntry
**Description**: Write a 12-bit RGB color value to the 256-color writable palette. Only affects Mode 4 (320×240×256).

**Arguments**:
- `$0002`: Palette index (0-255)
- `$0003`: RGB low byte (bits 7:4 = green, bits 3:0 = blue)
- `$0004`: RGB high byte (bits 3:0 = red, bits 7:4 unused) - **Execute instruction on update**

**Usage Example**:
```assembly
LDA #$00    ; Palette index 0
STA $0002
LDA #$0F    ; Green=0, Blue=15 (bright blue low bits)
STA $0003
LDA #$00    ; Red=0
STA $0004   ; Write palette entry and execute
```

#### $21 GetPaletteEntry
**Description**: Read a 12-bit RGB color value from the 256-color writable palette.

**Arguments**:
- `$0002`: Palette index (0-255) - **Execute instruction on update**

**Output**:
- `$000D`: RGB low byte (green[7:4], blue[3:0])
- `$000E`: RGB high byte (red[3:0], unused[7:4])

**Usage Example**:
```assembly
LDA #$05    ; Palette index 5
STA $0002   ; Execute read
; Wait for completion...
LDA $000D   ; Get RGB low byte
LDA $000E   ; Get RGB high byte (red in bits 3:0)
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
- 12-bit RGB (4 bits each: red[3:0], green[3:0], blue[3:0])
- Standard 640×480@60Hz timing (25.175MHz pixel clock)
- External resistor DAC for analog VGA levels

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
- **Bits 2:0**: Video mode number
  - `000` (0) = Text mode (80×30)
  - `001` (1) = Graphics Mode 1 (640×480×2 colors, 2 pages)
  - `010` (2) = Graphics Mode 2 (640×480×4 colors, 1 page)
  - `011` (3) = Graphics Mode 3 (320×240×16 colors, 2 pages)
  - `100` (4) = Graphics Mode 4 (320×240×256 colors, 1 page)
- **Bit 3**: Active page for display (modes with 2 pages: Mode 1 and Mode 3)
- **Bit 4**: Working page for writes (modes with 2 pages: Mode 1 and Mode 3)
- **Bit 5**: Hardware cursor enable (Text mode only: 1=visible, 0=hidden)
- **Bit 6**: Hardware cursor blink (Text mode only: 1=blinking, 0=solid)
- **Bit 7**: Reserved (currently unused)

**Examples**:
```assembly
; Text mode with cursor disabled
LDA #$00
STA $0000

; Text mode with solid cursor
LDA #$20    ; %00100000 = cursor enable
STA $0000

; Text mode with blinking cursor
LDA #$60    ; %01100000 = cursor enable + blink
STA $0000

; Graphics Mode 3 (320×240×16)
LDA #$03
STA $0000

; Graphics Mode 3, page 1 for display, page 0 for writes
LDA #$0B    ; %00001011 = page 1 display + mode 3
STA $0000
```

### Hardware Cursor (Text Mode Only)

The hardware cursor provides authentic CRT-style visual feedback in text mode.

**Appearance**:
- **Block cursor**: Fills entire character cell (8×16 pixels)
- **Color**: Uses foreground color of character at cursor position
- **Behavior**: Non-destructive overlay (character data unchanged)

**Position Control**:
- Set via **TEXT_POSITION ($01)** instruction
- Position is row/column based (0-29 rows, 0-79 columns)
- Independent of character write operations

**Blink Characteristics**:
- **Solid mode** (bit 6 = 0): Always visible
- **Blink mode** (bit 6 = 1): Toggles at ~3.75 Hz (VSYNC÷16)
  - 8 frames ON, 8 frames OFF
  - Synchronized to vertical refresh
  - Blinks **twice as fast** as character attribute blink

**Cursor over Blinking Character**:
- Cursor and character blink independently
- Results in 4-phase cycle over ~0.53 seconds:
  - Frames 0-7: Cursor visible (character obscured)
  - Frames 8-15: Character visible (cursor hidden)
  - Frames 16-23: Cursor visible over blank space
  - Frames 24-31: Both invisible

**Usage Example**:
```assembly
; Enable blinking cursor in text mode
LDA #$60    ; Cursor enable + blink
STA $0000   ; Set mode control

; Position cursor at row 10, column 40
LDA #$01    ; TEXT_POSITION instruction
STA $0001
LDA #10     ; Row 10
STA $0002
LDA #40     ; Column 40
STA $0003   ; Execute
```

The card provides authentic 1980s graphics capabilities with modern FPGA implementation benefits.
