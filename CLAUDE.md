# VibesGraphicsArray - Claude Context

## Project Overview
FPGA-based VGA graphics card implementation with text and graphics modes. Currently working on enhancing text mode functionality for better performance with text editors and interactive applications.

## Current Architecture

### Text Mode Module (`src/text_mode_module.v`)
- 80×30 character display with 16-pixel high characters
- Circular buffer scrolling system using `scroll_offset`
- Current instructions:
  - `TEXT_WRITE (0x00)`: Write character at cursor position
  - `TEXT_POSITION (0x01)`: Set cursor position  
  - `TEXT_CLEAR (0x02)`: Clear screen with attributes
  - `GET_TEXT_AT (0x03)`: Read character/attributes at position
  - `TEXT_COMMAND (0x04)`: Process ASCII control codes for CLI applications

### Performance Analysis
**Problem**: 1MHz CPU may be too slow for full screen redraws needed by text editors
- Full screen = 2,400 characters × 2 instructions = 4,800+ cycles  
- Estimated 10-20ms for complete redraw - too slow for responsive editing

**Solution**: Add hardware-accelerated block operations

## Implemented Features

### TEXT_COMMAND (0x04) - ASCII Control Codes
**Purpose**: Command-line interface support with simplified cursor behavior
**Implementation**: `src/text_mode_module.v:282-333`

**Supported Commands**:
- `$08` **Backspace**: Move cursor back 1 column and write space (stops at column 0)
- `$09` **Tab**: Advance cursor to next 8-column boundary
- `$0A` **Line Feed**: Move to column 0 of next row, scroll if at bottom
- `$0D` **Carriage Return**: Move to column 0 of current row
- `$7F` **Delete**: Write space at current cursor position

**Design Philosophy**: 
- CLI-oriented (no text shifting like traditional terminals)
- Backspace doesn't wrap to previous lines
- Commands work independently at any cursor position
- Uses `default_attributes` for consistent formatting

## Future Enhancements

### Potential Text Editor Instructions  
1. **TEXT_WRITE_AT (0x05)**: Write character directly at specified position
2. **TEXT_BLOCK_COPY (0x06)**: Hardware-accelerated rectangle copying
3. **TEXT_BLOCK_FILL (0x07)**: Fill rectangle with character/attributes
4. **SCROLL_UP (0x08)**: Manual viewport scrolling up
5. **SCROLL_DOWN (0x09)**: Manual viewport scrolling down

### Benefits for Text Editors
- **Document editing**: CPU manages document, VGA handles viewport
- **Efficient redraws**: Block operations instead of character-by-character
- **Viewport control**: Independent scrolling without document changes

## Historical Context Research

### EGA/VGA Control Characters
- **Hardware**: EGA/VGA cards were framebuffers - no built-in control character handling
- **BIOS**: INT 10h AH=0Eh teletype function handled CR, LF, backspace in software
- **Font**: Code Page 437 has displayable glyphs for ALL 256 codes (0x00-0xFF)
- **Scrolling**: BIOS provided scroll functions (INT 10h AH=06h/07h) via memory copying

### Architecture Comparison
**Original EGA/VGA**: Stateless framebuffer model
- Software manages everything (cursor, scrolling, wrapping)
- Direct memory access to 0xB8000
- Maximum flexibility but more CPU overhead

**Current Design**: TTY-style terminal controller  
- Hardware manages cursor state and automatic behaviors
- More efficient circular buffer scrolling
- Simpler software interface but less flexible

## Implementation Notes
- Font ROM contains displayable glyphs for ASCII control codes (0x08, 0x09, 0x0A, 0x0D, 0x7F)
- Current circular buffer approach is more efficient than EGA/VGA memory copying
- Need to balance between terminal-like ease of use and framebuffer-like flexibility

## Files Modified
- `src/text_mode_module.v` - Main text mode implementation with TextCommand support
- `src/cpu_interface.v` - CPU interface with TEXT_COMMAND instruction integration
- `specification.md` - Updated with TextCommand instruction documentation
- `.gitignore` - Added impl/ directory exclusion for Gowin FPGA build artifacts
- `tests/tb_text_mode.v` - Test bench (needs TextCommand test cases)
- `font_8x16.mem` - 8×16 font ROM data (Code Page 437)

## Current Status
- **TextCommand (0x04)** implementation complete with corrected ASCII codes
- Fixed missing cpu_interface.v integration (instruction was not recognized)
- CLI applications can now use backspace, tab, line feed, carriage return, and delete
- Command-line editing behavior optimized for interactive shell applications
- Hardware tested and confirmed working

## Mode 5: Sprite/Tile Graphics - Design Complete with Hardware Scrolling

### Overview
NES-style sprite/tile graphics mode for retro game development. See `MODE5_SPRITE_DESIGN.md` for complete specification.

### Key Features
- **Resolution**: 320×240 pixels, 8-bit direct RGB (64 colors)
- **Tile-based background**: 40×30 grid of 8×8 tiles, 4 tilemap pages
- **Hardware scrolling**: Pixel-perfect smooth scrolling with 2×2 page grid layout
- **Hardware sprites**: 64 total, 8 per scanline (NES-equivalent)
- **Sprite attributes**: Stored in registers for parallel evaluation
- **Priority control**: Per-tile foreground/background with sprite compositing
- **VBLANK & Scanline interrupts**: Safe update windows for 60fps animation and raster effects

### Hardware Scrolling (NEW)
- **2×2 Page Grid**: Pages arranged as 640×480 pixel space with horizontal mirroring
  - Pages 0-1: Top row (horizontal scrolling pair)
  - Pages 2-3: Bottom row (horizontal scrolling pair)
  - Seamless wrapping: Page 0 ↔ Page 1, Page 2 ↔ Page 3
- **SCROLL_X**: 0-639 pixels (9 bits), wraps automatically at 640
- **SCROLL_Y**: 0-479 pixels (9 bits), wraps automatically at 480
- **Use cases**: Mario-style platformers, Zelda overworld, vertical shooters
- **CPU streaming**: Update columns/rows at edges during VBLANK (NES/Dragon Warrior technique)

### Interrupt System (NEW)
**Status Register ($000F)** optimized for BIT instruction:
- Bit 0: BUSY (0=ready, 1=busy)
- Bit 1: ERROR
- **Bit 6: VBLANK flag** → V flag via BIT
- **Bit 7: Scanline flag** → N flag via BIT

**VBLANK Interrupt**:
- Fires at start of vertical blanking (~1.43ms, ~1430 CPU cycles at 1MHz)
- Safe window for sprite/tilemap/palette updates
- Enable via Mode Control Register ($0000 bit 5)

**Scanline Interrupt**:
- Fires at configurable scanline (0-479 via SetScanline instruction)
- Enables split-screen scrolling, sprite multiplexing, parallax effects
- Enable via Mode Control Register ($0000 bit 6)

**BIT Instruction Usage**:
```assembly
BIT $000F   ; Test status (clears interrupt flags)
            ; Bit 7 → N flag (Scanline)
            ; Bit 6 → V flag (VBLANK)
BMI ScanlineInterrupt
BVS VBlankInterrupt
```

### Memory Architecture (38,168 bytes used / 76,800 total)
- **2 sprite sheet pages**: 32,768 bytes (`$0000-$7FFF`)
  - 512 total sprite patterns (256 per page)
  - Linear storage for simple addressing
  - Instant page switching
- **4 tilemap pages**: 5,400 bytes (`$8000-$9517`)
  - Sprite index plane: 1,200 bytes per page
  - Priority bit plane: 150 bytes per page (8 tiles packed per byte)
- **64 sprite attributes**: In flip-flops (~2048 FFs)
  - X/Y position, sprite index, flip H/V, enable
  - Parallel evaluation (all 64 checked simultaneously)
  - Can update anytime (not restricted to VBLANK)
- **Remaining**: 38,632 bytes for future expansion

### Complete Instruction Set
**Sprite/Tile Operations:**
- **$20 LoadSprite**: Write sprite pixel data (page, index, offset, data)
- **$21 SetTile**: Set tile with auto priority handling (page, tile index, sprite index, priority)
- **$22 SetSpriteAttr**: Configure moving sprite (sprite#, X, Y, sprite index, flags)
- **$23 SetSpritePage**: Switch active sprite sheet page (0-1)
- **$24 SetTilemapPage**: Switch active tilemap page (0-3)
- **$25 WriteVRAM**: Raw VRAM write for bulk loading (16-bit address, data)
- **$26 ReadVRAM**: Raw VRAM read for debugging (16-bit address)

**Scrolling (NEW):**
- **$27 SetScrollX**: Set horizontal scroll offset (0-639 pixels)
- **$28 SetScrollY**: Set vertical scroll offset (0-479 pixels)
- **$29 SetScroll**: Set both X and Y atomically
- **$2A SetScanline**: Set scanline interrupt trigger (0-479)
- **$2B GetScrollX**: Read current SCROLL_X value
- **$2C GetScrollY**: Read current SCROLL_Y value
- **$2D GetScanline**: Read current scanline trigger value

### CPU Interface Architecture
- **$0000**: Mode Control Register (read/write)
- **$0001**: Instruction opcode (write)
- **$0002-$000C**: Instruction arguments (11 bytes available)
- **$000D-$000E**: Result registers (read, for Get instructions)
- **$000F**: Status register (read, optimized for BIT instruction)

### Rendering Pipeline
**Display Configuration:**
- Logical resolution: 320×240 pixels
- Physical VGA output: 640×480 @ 25.175 MHz
- Each logical pixel displayed as 2×2 block (pixel doubling horizontal/vertical)
- Coordinate mapping: `logical = vga >> 1`

**Horizontal Blanking (~320 VGA clocks):**
- Sequential sprite evaluation: up to 65 clocks worst case
  - Clock 0: Parallel match detection (64-bit match vector)
  - Clocks 1-64: Sequential scan for first 8 matching sprites (early exit when 8 found)
  - Typical case: 20-30 clocks
- Read 45-46 tilemap/priority bytes: 45 clocks (46 if crossing page boundary)
- Read sprite line buffers (up to 8 sprites × 8 pixels): 64 clocks
- Total: ~174 clocks worst case, 146 clocks spare ✓

**Active Scanline (640 VGA clocks = 320 logical pixels × 2):**
- Apply scroll offsets to determine source page and tile coordinates
- Background tiles rendered just-in-time (1 VRAM read per logical pixel)
- Sprites composited from pre-loaded line buffers
- Priority: Foreground tiles → Sprites 0-7 → Background tiles
- Same pixel output twice horizontally, same scanline rendered twice vertically

### Resource Estimates
- **Logic**: ~1000 LUTs (16% of 20K available)
- **Registers**: ~3000 flip-flops (29% of 15K available)
- **BSRAM**: 0 additional (uses existing video RAM)

### Design Decisions
- **Linear sprite storage** vs 2D sheet layout (simpler addressing, preprocessor handles conversion)
- **Sprite attributes in registers** vs BRAM (parallel evaluation, anytime updates)
- **Single line buffer** vs double-buffered (simpler, 8 sprites sufficient for NES-style games)
- **Free flip H/V** (combinational logic, no extra clocks)
- **Sequential sprite scan** vs hardware priority encoder (simple, fits timing budget, easy to verify)
- **2×2 pixel doubling** (320×240 logical → 640×480 VGA, doubles timing budget for hblank operations)
- **2×2 page grid with horizontal mirroring** (matches NES vertical mirroring model)
- **Status register bits 6/7 for interrupts** (optimized for 6502 BIT instruction)

### Asset Workflow
1. Design sprites/tiles in Aseprite/GIMP (visual 2D layout)
2. Export to .TGA format
3. Preprocessor converts to:
   - Linear sprite data
   - Tilemap sprite indices
   - Packed priority bit-plane
4. Bulk load via WriteVRAM instruction
5. Update sprite positions via SetSpriteAttr (60fps)
6. Update scroll registers via SetScrollX/Y for smooth camera movement

### Future: 256-Color Palette
- Shared 256×12bit palette for Mode 4 & 5 (always active)
- ~900 LUTs in distributed RAM (~4.5% of available)
- New `SET_PALETTE_ENTRY` instruction
- Requires 12-bit RGB DAC hardware (4-4-4, upgrade from current 2-2-2)
- 4096 colors available, smoother gradients and better color fidelity
- Enables palette effects: color cycling, fades, screen flashes
- Binary-weighted resistor DAC values calculated (0.7V into 75Ω VGA, ±2.5% error)
- Status: Design complete with resistor values, pending hardware build

## Mode 5 Implementation Plan - In Progress

### Current Status
- **Branch**: `feature/mode5-implementation`
- **Phase**: Ready to start Phase 1 (Static Background Tiles)
- **Strategy**: Incremental implementation with 12 phases for straightforward verification

### Implementation Phases

**Phase 1: Static Background Tiles** ← NEXT
- Allocate VRAM for sprite sheet (256 sprites × 64 bytes) and tilemap (1,200 bytes)
- Hardcode test patterns in Verilog (red/green checkerboard)
- Implement tile fetching during hblank (40-byte buffer)
- Implement pixel rendering with 2×2 doubling
- **Success**: Display checkerboard on power-on

**Phase 2: CPU Instructions for Tilemap Setup**
- Add $25 WriteVRAM (raw VRAM write)
- Add $21 SetTile (simplified, no priority yet)
- **Success**: CPU writes "HELLO" using tiles

**Phase 3: Multiple Tilemap Pages**
- Expand to 4 × 1,200 byte tilemap pages
- Add $24 SetTilemapPage instruction
- **Success**: Switch between 4 different screens

**Phase 4: Priority Bit-Plane**
- Add 150-byte priority plane per page (8 tiles packed per byte)
- Update $21 SetTile to accept priority argument
- **Success**: Mark foreground tiles (matters when sprites added)

**Phase 5: Hardware Scrolling**
- Add SCROLL_X/Y internal registers (9 bits each)
- Add $27 SetScrollX, $28 SetScrollY instructions
- Implement coordinate mapping with page boundary handling
- **Success**: Smooth scroll through 2×2 page grid

**Phase 6: Sprite Attribute Registers**
- 64 × 4-byte register file in flip-flops
- Add $22 SetSpriteAttr instruction
- **Success**: Write/read sprite attributes

**Phase 7: Sprite Evaluation**
- Parallel match detection (all 64 sprites)
- Sequential priority scan (find first 8)
- **Success**: Debug signals show correct sprites selected

**Phase 8: Sprite Line Buffer Loading**
- 8 × 8-byte line buffers (64 bytes flip-flops)
- Pre-fetch sprite pixels during hblank
- Handle flip H/V flags
- **Success**: Line buffers contain correct data

**Phase 9: Sprite Compositor**
- Check X position overlap for 8 active sprites
- Priority compositor (foreground tiles → sprites → background tiles)
- **Success**: Sprites display over scrolling background

**Phase 10: VBLANK Interrupt**
- VBLANK flag (bit 6 in $000F)
- VBLANK enable (bit 5 in $0000)
- IRQ output logic
- **Success**: IRQ fires 60Hz, smooth updates

**Phase 11: Scanline Interrupt**
- SCANLINE_TRIGGER register via $2A instruction
- Scanline flag (bit 7 in $000F)
- **Success**: Split-screen effect working

**Phase 12: Get Instructions & Polish**
- Add $2B GetScrollX, $2C GetScrollY, $2D GetScanline
- Add $26 ReadVRAM
- Bug fixes and optimizations
- **Success**: Full game demo

### Key Design Decisions from Research
- **NES nametables**: 256×240 pixels (same as screen size, not larger)
- **NES scrolling**: Used 2 physical nametables with mirroring, CPU streamed tile updates
- **Circular buffer technique**: 2-tile border around visible area for CPU updates
- **Our advantage**: 4 full independent pages (better than NES's 2 physical pages)

## Project Roadmap

### Hardware Development Schedule
1. **PCB Migration**: Move VGA card from breadboard to PCB
2. **SD Card Interface (Breadboard)**: 6522 VIA → SPI → SD Card, test filesystem drivers
3. **SD Card Parallel Interface**: Evaluate parallel design for faster access
4. **SD Card PCB**: Build production hardware for winning design (SPI vs parallel)
5. **Mode 5 Implementation**: In progress (12-phase incremental approach)
6. **Sound System**: FPGA OPL2 (Yamaha) + 1-bit delta-sigma DAC

### Software/Firmware Tasks
- Filesystem driver development and testing
- Asset preprocessor tool (TGA → sprite/tilemap data)
- Mode 5 sprite compositor Verilog implementation (in progress)
- Game engine / demo applications
- Audio synthesis and mixing