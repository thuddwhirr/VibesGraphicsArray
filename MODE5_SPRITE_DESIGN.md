# Mode 5: Sprite/Tile Graphics Mode - Design Document

## Overview
Mode 5 implements a sprite-based graphics system inspired by NES/retro game consoles, using existing video RAM for sprite storage and tilemap-based backgrounds.

## Display Configuration
- **Logical Resolution**: 320×240 pixels (Mode 5)
- **Physical VGA Output**: 640×480 @ 25.175 MHz (each logical pixel displayed as 2×2 block)
- **Pixel Doubling**: Logical coordinates = VGA coordinates >> 1 (horizontal and vertical)
- **Color Depth**: 8 bits per pixel (64-color direct RGB, bypassing palette like Mode 4)
- **Background**: 40×30 tile grid (8×8 pixel tiles)
- **Moving Sprites**: Hardware sprite compositor with priority/transparency

## Memory Architecture

### Video RAM Layout (76,800 bytes total)
- **Sprite Sheets**: 2 pages × 16,384 bytes = 32,768 bytes (`$0000-$7FFF`)
  - Page 0: `$0000-$3FFF` (256 sprites)
  - Page 1: `$4000-$7FFF` (256 sprites)
  - Each sprite: 8×8 pixels × 8 bits/pixel = 64 bytes
  - Linear addressing: sprite N at offset `N * 64`
  - 64-color palette using 8-bit direct RGB (RRR GGG BB)

- **Tilemap Pages**: 4 pages × 1,350 bytes = 5,400 bytes (`$8000-$9517`)
  - Page 0: `$8000-$8545` (1,350 bytes)
  - Page 1: `$8546-$8A8B` (1,350 bytes)
  - Page 2: `$8A8C-$8FD1` (1,350 bytes)
  - Page 3: `$8FD2-$9517` (1,350 bytes)
  - Each page contains two planes:
    - **Sprite Index Plane**: 40×30 = 1,200 bytes (1 byte per tile)
    - **Priority Bit Plane**: 40×30 bits = 150 bytes (8 tiles per byte, packed)
  - Each sprite index byte: sprite pattern to use (0-255)
  - Each priority bit: 0=background (behind sprites), 1=foreground (in front of sprites)
  - Instant page switching for screen transitions

- **Sprite Attributes**: Stored in flip-flops (not video RAM)
  - 64 sprites × 4 bytes = 256 bytes in registers
  - X position (9 bits) - supports 0-511 for smooth scrolling
  - Y position (8 bits) - supports 0-255
  - Sprite index (8 bits) - which sprite pattern to use
  - Flags (8 bits) - flip X/Y, enable, X bit 8

- **Used**: 38,168 bytes (49.7% of VRAM)
- **Remaining**: 38,632 bytes (`$9518-$FFFF`) for:
  - Additional sprite sheet pages
  - Additional tilemap pages
  - Animation frame buffers
  - Particle effect data
  - Future expansion

### Tilemap Storage Format

**Sprite Index Plane** (1,200 bytes per page):
- Address: `tilemap_base + (tile_y * 40 + tile_x)`
- Value: Sprite index 0-255

**Priority Bit Plane** (150 bytes per page):
- Address: `tilemap_base + 1200 + (tile_y * 5 + tile_x / 8)`
- Bit position: `tile_x % 8`
- Value: 0=background (behind sprites), 1=foreground (in front of sprites)
- 8 tiles packed per byte (bits 0-7 = tiles 0-7 in that row chunk)

### Sprite Attribute Format (2-4 bytes per sprite)
```
Byte 0: X position [7:0]
Byte 1: Y position [7:0]
Byte 2: Sprite index [7:0]
Byte 3: Flags
  - Bit 0: X position [8] (for >255)
  - Bit 1: Flip horizontally
  - Bit 2: Flip vertically
  - Bit 3: Reserved (priority is determined by sprite order)
  - Bit 4: Enable
  - Bits 5-7: Reserved
```

## Rendering Pipeline

### Background Rendering (Tile-Based)

**Critical Constraint**: Only 1 video RAM read per pixel clock (25.175 MHz)

**Pixel Doubling**: Each logical 320×240 pixel is rendered twice horizontally (VGA outputs 640 pixels). Same pixel value output on consecutive clocks.

**Scanline Doubling**: Each logical scanline is rendered twice vertically (VGA outputs 480 lines). Same scanline rendered on consecutive VGA rows.

**Coordinate Mapping**:
- `logical_x = vga_pixel_x >> 1` (0,0,1,1,2,2,3,3...)
- `logical_y = vga_scanline_y >> 1` (0,0,1,1,2,2,3,3...)

**Two-Stage Pipeline:**

**Stage 1: Horizontal Blanking (~320 VGA clocks)**
1. Read 40 sprite indices from video RAM for next scanline's tiles
   - Address: `tilemap_base + (logical_scanline_y / 8) * 40`
   - Store in 40-byte tile index buffer
2. Read 5 priority bytes (40 bits packed) from video RAM
   - Address: `tilemap_base + 1200 + (logical_scanline_y / 8) * 5`
   - Store in 5-byte priority buffer (or unpack to 40-bit flags)
3. **Total: 45 reads** (fits easily in 320 clocks)

**Stage 2: Active Scanline (640 VGA clocks = 320 logical pixels × 2)**
1. Calculate which tile: `tile_num = logical_pixel_x / 8` (0-39)
2. Read sprite index from buffer: `sprite_idx = tile_buffer[tile_num]`
3. Read priority flag from buffer: `priority = priority_buffer[tile_num]` or extract from packed byte
4. Calculate pixel offset within sprite: `offset = (logical_scanline_y % 8) * 8 + (logical_pixel_x % 8)`
5. **Single video RAM read**: `color = sprite_data[sprite_idx * 64 + offset]`
6. Pass background color + priority flag to compositor
7. **Output same pixel value for 2 consecutive VGA clocks** (pixel doubling)

**Key Design Points**:
- 40-byte tile index buffer uses ~320 flip-flops
- 5-byte priority buffer uses ~40 flip-flops (or 40 bits unpacked)
- Only 1 video RAM access per pixel clock ✓
- Video RAM Port A: CPU writes
- Video RAM Port B: Display reads (tilemap/priority during blanking, sprite pixels during active)

### Moving Sprite Rendering

**Stage 1: Horizontal Blanking (~320 VGA clocks)**
1. **Sprite Evaluation** (Sequential scan - up to 65 clocks worst case):
   - **Clock 0**: Parallel match detection (combinational logic)
     - All 64 sprite attribute registers checked simultaneously
     - For each sprite: `match[i] = enable[i] && (y[i] <= next_scanline) && (next_scanline < y[i] + 8)`
     - Result: 64-bit match vector
   - **Clocks 1-64**: Sequential priority scan
     - Initialize: `sprite_count = 0`, `scan_index = 0`
     - For each iteration while `scan_index < 64` and `sprite_count < 8`:
       - If `match[scan_index]`: record `active_sprite[sprite_count] = scan_index`, increment `sprite_count`
       - Always increment `scan_index`
     - Early exit when `sprite_count == 8` (all slots filled)
   - **Performance**: Best case 8 clocks, typical 20-30 clocks, worst case 64 clocks
   - **Result**: `active_sprite[0..sprite_count-1]` contains sprite indices in priority order

2. **Tilemap/Priority Buffer Loading** (45 reads):
   - Read 40 sprite indices for next scanline's tiles
   - Read 5 priority bytes (40 bits packed)
   - Can execute in parallel with sprite evaluation (uses VRAM, not registers)

3. **Sprite Line Buffer Loading** (64 reads):
   - For each active sprite (0 to `sprite_count-1`), read 8 pixels from video RAM
   - Store in sprite line buffers (8 bytes × 8 sprites = 64 bytes in flip-flops)
   - Calculate sprite data address: `sprite_data[sprite_idx * 64 + (logical_scanline_y - sprite_y) * 8]`
   - If `sprite_count < 8`, fewer reads needed
   - **Total: ~174 clocks worst case (65 eval + 45 tilemap + 64 sprites) with 146 clocks spare**

**Stage 2: Active Scanline (640 VGA clocks = 320 logical pixels × 2)**
1. **Parallel Sprite Compositor**:
   - Background pixel from tile pipeline (from video RAM)
   - For each active sprite (0-7), check if X position overlaps current logical pixel
   - Read sprite pixel from line buffer (no video RAM access - parallel registers)
   - Check transparency (color 0 = transparent)
   - Apply fixed priority scheme (sprite 0 = highest priority)

2. **Priority Resolution (First-Match-Wins)**:
   - Check sprite 0: If pixel not transparent and X matches → use sprite 0 color
   - Check sprite 1: If pixel not transparent and X matches → use sprite 1 color
   - Continue through sprite 7
   - If all sprites transparent → use background pixel color

3. **Final Output**:
   - Selected sprite color (if any sprite matched)
   - OR background color (if all sprites transparent)
   - **Output same pixel value for 2 consecutive VGA clocks** (pixel doubling)

**Performance**:
- Background: 1 video RAM read per logical pixel (45 tilemap/priority bytes + 320 sprite pixels per logical scanline, rendered twice for VGA output)
- Moving sprites: Sequential evaluation (65 clocks worst case) + pre-loaded during blanking (64 reads for up to 8 sprites)
- **Total horizontal blanking usage: ~174 clocks worst case out of ~320 available (146 clocks spare)**
- **8 sprites per scanline maximum** (matches NES capability)
- Total active sprites: 64 supported (all evaluated each logical scanline via sequential scan, top 8 displayed)
- **Note**: Same scanline rendered twice vertically (no additional work for even VGA scanlines)
- **Optimization**: Tilemap reads can overlap with sprite evaluation (parallel operations on different resources)

## Memory Addressing Scheme

### Sprite Sheet Access
- Base address: 0x0000
- Sprite N address: `N * 64` (0x0000, 0x0040, 0x0080, ...)
- Pixel offset within sprite: `(row * 8) + col`
- Full address: `(sprite_index * 64) + (row * 8) + col`

### Tilemap Access
- Base address: 0x4000 (after 256 sprites)
- Page N base: `0x4000 + (N * 1350)`

**Sprite Index Plane:**
- Tile at (X,Y): `page_base + (Y * 40) + X`

**Priority Bit Plane:**
- Priority byte for tiles at Y, X÷8: `page_base + 1200 + (Y * 5) + (X / 8)`
- Bit position within byte: `X % 8`

### Sprite Attribute Registers
- **Implementation**: 64 sprite attribute sets stored in flip-flops (not BRAM)
- **Size**: 64 sprites × 4 bytes = 256 bytes = ~2048 flip-flops (~13% of available registers)
- **Access**: CPU writes via SetSpriteAttr instruction, parallel read for evaluation
- **Benefits**: All 64 sprites can be evaluated simultaneously in combinational logic

## Instruction Set

### Sprite/Tile Instructions

#### $20 LoadSprite
**Description**: Write individual sprite pixel data to sprite sheet.

**Arguments**:
- `$0002`: Sprite sheet page (0-1)
- `$0003`: Sprite index (0-255)
- `$0004`: Offset within sprite (0-63)
- `$0005`: Pixel data (8-bit color) - **Execute on update**

**Address calculation**: `page * 16384 + sprite_index * 64 + offset`

**Usage**: Write sprite data byte-by-byte during development/testing

#### $21 SetTile
**Description**: Set background tilemap entry by tile index with automatic priority bit handling.

**Arguments**:
- `$0002`: Tilemap page (0-3)
- `$0003`: Tile index low byte
- `$0004`: Tile index high byte (0-4, max value 1199)
- `$0005`: Sprite index to use (0-255)
- `$0006`: Priority bit (0=background, 1=foreground) - **Execute on update**

**Hardware behavior**:
- Writes sprite index to: `tilemap_base + tile_index`
- Calculates priority bit address: `tilemap_base + 1200 + (tile_index / 8)`
- Updates priority bit at position: `tile_index % 8`

**Note**: Abstracts away priority bit packing - usable for runtime tile editing

#### $22 SetSpriteAttr
**Description**: Configure moving sprite attributes (writes to sprite attribute registers).

**Arguments**:
- `$0002`: Sprite number (0-63)
- `$0003`: X position (low 8 bits)
- `$0004`: Y position (0-255)
- `$0005`: Sprite index (0-255)
- `$0006`: Flags byte - **Execute on update**
  - Bit 0: X position bit 8 (for X = 256-511)
  - Bit 1: Flip horizontal
  - Bit 2: Flip vertical
  - Bit 3: Reserved
  - Bit 4: Enable sprite
  - Bits 5-7: Reserved

**Note**: Updates sprite attribute registers directly (not video RAM). Can be updated anytime, not restricted to VBLANK.

#### $23 SetSpritePage
**Description**: Switch active sprite sheet page.

**Arguments**:
- `$0002`: Active sprite sheet page (0-1) - **Execute on update**

**Usage**: Instantly switch between two 256-sprite sets (player/enemies vs effects/UI, etc.)

#### $24 SetTilemapPage
**Description**: Switch active background tilemap page.

**Arguments**:
- `$0002`: Active tilemap page (0-3) - **Execute on update**

**Usage**: Instant screen transitions, double-buffered tile updates

#### $25 WriteVRAM
**Description**: Raw video memory write for bulk loading preprocessed data.

**Arguments**:
- `$0002`: Address low byte
- `$0003`: Address high byte
- `$0004`: Data byte - **Execute on update**

**Address range**: `$0000-$FFFF` (full 64KB address space, 38,168 bytes used)

**Usage**: Fast bulk loading of sprite sheets and tilemaps from disk

#### $26 ReadVRAM
**Description**: Raw video memory read for inspection and debugging.

**Arguments**:
- `$0002`: Address low byte
- `$0003`: Address high byte - **Execute on update**

**Returns**: Data byte in status/read register

**Usage**: Verify loaded data, debugging, collision detection helpers

#### $27 SetScrollX
**Description**: Set horizontal scroll offset for smooth scrolling.

**Arguments**:
- `$0002`: SCROLL_X low byte (bits 0-7)
- `$0003`: SCROLL_X high bit (bit 0 = SCROLL_X bit 8) - **Execute on update**

**Range**: 0-639 pixels (wraps automatically at 640)

**Usage**:
- Horizontal scrolling games (Mario): Increment each frame for smooth movement
- Open world games: Update based on camera position
- Set to 0 for non-scrolling games or room-based games

**Note**: Can be updated anytime, but typically updated during VBLANK for tear-free scrolling

#### $28 SetScrollY
**Description**: Set vertical scroll offset for smooth scrolling.

**Arguments**:
- `$0002`: SCROLL_Y low byte (bits 0-7)
- `$0003`: SCROLL_Y high bit (bit 0 = SCROLL_Y bit 8) - **Execute on update**

**Range**: 0-479 pixels (wraps automatically at 480)

**Usage**:
- Vertical scrolling games: Increment each frame for smooth movement
- Open world games: Update based on camera position
- Zelda-style room transitions: Animate from 0→240 or 240→0
- Set to 0 for non-scrolling games

**Note**: Can be updated anytime, but typically updated during VBLANK for tear-free scrolling

#### $29 SetScroll (Combined)
**Description**: Set both X and Y scroll offsets with a single instruction (optional convenience instruction).

**Arguments**:
- `$0002`: SCROLL_X low byte
- `$0003`: SCROLL_X high bit (bit 0)
- `$0004`: SCROLL_Y low byte
- `$0005`: SCROLL_Y high bit (bit 0) - **Execute on update**

**Usage**: Update both scroll registers atomically during VBLANK

**Note**: Equivalent to calling SetScrollX then SetScrollY, but may be more efficient

#### $2A SetScanline
**Description**: Set scanline interrupt trigger position.

**Arguments**:
- `$0002`: SCANLINE_TRIGGER low byte (bits 0-7)
- `$0003`: SCANLINE_TRIGGER high bit (bit 0) - **Execute on update**

**Range**: 0-479 (physical VGA scanlines)

**Usage**:
- Split-screen effects: Set to scanline where screen region changes
- Sprite multiplexing: Set to scanline where sprites should be repositioned
- Typically set once during initialization, not updated frequently

**Note**: Must enable scanline interrupt in Mode Control Register ($0000 bit 6) for interrupt to fire

#### $2B GetScrollX
**Description**: Read current horizontal scroll offset.

**Arguments**: None - **Execute immediately**

**Returns**:
- `$000D`: SCROLL_X low byte (bits 0-7)
- `$000E`: SCROLL_X high bit (bit 0 in LSB position, bits 1-7 are 0)

**Usage**: Read back current scroll position for calculations or debugging

#### $2C GetScrollY
**Description**: Read current vertical scroll offset.

**Arguments**: None - **Execute immediately**

**Returns**:
- `$000D`: SCROLL_Y low byte (bits 0-7)
- `$000E`: SCROLL_Y high bit (bit 0 in LSB position, bits 1-7 are 0)

**Usage**: Read back current scroll position for calculations or debugging

#### $2D GetScanline
**Description**: Read current scanline interrupt trigger position.

**Arguments**: None - **Execute immediately**

**Returns**:
- `$000D`: SCANLINE_TRIGGER low byte (bits 0-7)
- `$000E`: SCANLINE_TRIGGER high bit (bit 0 in LSB position, bits 1-7 are 0)

**Usage**: Read back scanline trigger setting for debugging or dynamic adjustment

## Hardware Implementation Notes

### Dual-Port BRAM Usage
- **Port A**: CPU interface (write sprite data, tilemap)
- **Port B**: Display rendering (read sprite pixels, tilemap)
- **Note**: Video RAM BSRAM already at 100% capacity (46/46 blocks used)
- **Sprite attributes**: Not stored in BRAM - implemented as register file in flip-flops

### Sprite Compositor Module
- Parallel to existing graphics_mode_module
- Shares video timing signals
- Outputs RGB when Mode 5 active
- Components:
  - Sprite attribute register file (64 sprites × 4 bytes in flip-flops)
  - Parallel sprite evaluator (combinational logic, all 64 sprites checked simultaneously)
  - Tile background renderer (reuse text mode logic)
  - 8 sprite line buffers (8 bytes each, implemented in flip-flops)
  - 8 parallel sprite comparators and pixel selectors
  - Priority compositor (blend sprites with background)

### Resource Requirements (Estimated)
- **Logic**: ~1000 LUTs (5% of 20K available)
  - Sprite evaluation: ~400 LUTs (64 parallel comparators)
  - Compositor/priority: ~400 LUTs
  - Control logic: ~200 LUTs
- **Registers**: ~3000 flip-flops (20% of 15K available)
  - Sprite attributes: ~2048 FFs (64 sprites × 32 bits)
  - Sprite line buffers: ~512 FFs (8 sprites × 64 bits)
  - Control/timing: ~440 FFs
- **BSRAM**: 0 additional (all sprite data uses existing video RAM)
- **Total utilization**: ~16% logic, ~29% registers

### Performance Considerations
- **Logical resolution**: 320×240 pixels (rendered as 640×480 VGA output via 2×2 pixel doubling)
- **Background**: 320 logical pixels/scanline, just-in-time tile reads (proven in text mode)
- **Sprites**: 8 sprites per logical scanline maximum (matches NES capability)
- **Horizontal blanking budget**: ~174 clocks used worst case (65 eval + 45 tilemap + 64 sprites), **146 clocks spare**
- **Sprite evaluation**: Sequential scan algorithm
  - Parallel match detection (1 clock) generates 64-bit match vector
  - Sequential priority scan (up to 64 clocks) finds first 8 matching sprites
  - Early exit optimization when 8 sprites found
  - Typical case: 20-30 clocks total
- **Total sprites**: 64 active sprites supported (all evaluated each logical scanline, top 8 displayed)
- **Pixel clock**: 25.175 MHz (VGA standard)
- **Rendering efficiency**: Each logical scanline rendered twice vertically with no additional computation

## Comparison to Other Systems

### NES (Reference)
- 256×240 resolution
- 64 total sprites
- 8 sprites per scanline (hardware limit)
- 4 colors per sprite (3 + transparent)

### Mode 5 Comparison
- Higher resolution (320×240 vs 256×240)
- 64 colors per sprite (vs 4 colors)
- 8 sprites per scanline (matches NES)
- 64 total active sprites (matches NES OAM)
- **Parallel sprite evaluation** (all 64 checked simultaneously vs NES sequential)
- Per-tile foreground/background priority (NES had limited priority control)
- Flexible memory allocation
- 4 instant tilemap page switching

## Future Enhancements

### 256-Color Palette (Planned)

**Overview**: Shared 256×12bit palette for Mode 4 and Mode 5, always active (no bypass mode).

**Hardware Requirements**:
- **Storage**: 256 entries × 12 bits = 3,072 bits in distributed RAM (LUT-based)
- **Resource cost**: ~900 LUTs (~4.5% of 20K available) ✓
- **Implementation**: Dual-port LUT RAM (CPU write port, display read port)
- **Color format**: 12-bit RGB (RRRR GGGG BBBB, 4096 colors available)

**Display Pipeline**:
- Mode 4: 8-bit pixel from VRAM → palette lookup → 12-bit RGB output
- Mode 5: 8-bit color from sprite/tile compositor → palette lookup → 12-bit RGB output
- Same palette shared between both modes

**CPU Interface**:
- **New instruction**: `SET_PALETTE_ENTRY` (e.g., opcode `$27`)
- **Arguments**:
  - `$0002`: Palette index (0-255)
  - `$0003`: RGB value low byte (bits 0-7: GGGG BBBB)
  - `$0004`: RGB value high byte (bits 0-3: RRRR) - **Execute on update**
- **Usage**: Load custom palettes for images, palette animation effects

**Benefits**:
- Mode 4: True 256-color images with artist-defined palettes
- Mode 5: 256 unique colors for sprites/tiles (vs current 64-color direct RGB)
- 4096 color palette (vs 64 direct RGB colors) - smoother gradients and better color fidelity
- Palette effects: color cycling, fade to black/white, screen flashes, palette rotation
- Simpler hardware: shared palette for both modes

**Hardware Dependencies**:
- Requires 12-bit RGB DAC hardware (4 bits per color channel)
- Current 6-bit RGB (2-2-2) hardware must be upgraded first

**DAC Resistor Values (Binary-Weighted, 0.7V max into 75Ω VGA termination):**

| Bit | Binary | Target Voltage | Calculated R | Practical Resistors | Error  |
|-----|--------|----------------|--------------|---------------------|--------|
| 0   | 0001   | 0.0467V        | 5224.8Ω      | 4.7kΩ + 560Ω (5.26kΩ) | -0.5% |
| 1   | 0010   | 0.0933V        | 2577.7Ω      | 2.2kΩ + 330Ω (2.53kΩ) | +2.0% |
| 2   | 0100   | 0.1867V        | 1250.7Ω      | 1.0kΩ + 220Ω (1.22kΩ) | +2.5% |
| 3   | 1000   | 0.3733V        | 588.0Ω       | 560Ω + 22Ω (582Ω)     | -1.0% |

**Per Color Channel (R, G, or B):**
- Bit 0 (LSB): 4.7kΩ + 560Ω series (or 5.1kΩ single resistor)
- Bit 1: 2.2kΩ + 330Ω series (= 2.53kΩ)
- Bit 2: 1.0kΩ + 220Ω series (= 1.22kΩ)
- Bit 3 (MSB): 560Ω + 22Ω series (= 582Ω)

**Full RGB Implementation:**
- 3 color channels × 4 bits = 12 resistor networks
- Maximum output: 0.7V (1111 binary = all bits HIGH)
- All errors < ±2.5%, excellent linearity
- Total: 24 resistors (using series combinations) or 12 resistors (if exact values available)

**Status**: Design complete, pending 12-bit color hardware implementation.

### Hardware Scrolling

**Overview**: Pixel-level smooth scrolling with automatic page wrapping, supporting both horizontal scrollers (Mario-style) and open-world games (Zelda-style).

#### Scroll Registers

**SCROLL_X Register** (9 bits, $0010):
- **Range**: 0-639 pixels (covers two 320-pixel pages side-by-side)
- **Wrapping**: Automatically wraps at 640 (back to 0)
- **Page mapping**:
  - 0-319: Primary viewing Page 0
  - 320-639: Primary viewing Page 1
  - At boundaries, viewport spans both pages

**SCROLL_Y Register** (9 bits, $0011):
- **Range**: 0-479 pixels (covers two 240-pixel pages stacked)
- **Wrapping**: Automatically wraps at 480 (back to 0)
- **Page mapping**:
  - 0-239: Primary viewing Page 0 or 1 (depending on SCROLL_X)
  - 240-479: Primary viewing Page 2 or 3 (depending on SCROLL_X)

#### Page Grid Layout (2×2 with Horizontal Mirroring)

```
        SCROLL_X →
         0-319   320-639
       ┌─────────┬─────────┐
  0-239│ Page 0  │ Page 1  │  SCROLL_Y
       │         │         │     ↓
240-479│ Page 2  │ Page 3  │
       └─────────┴─────────┘
```

**Horizontal Mirroring** (Pages 0↔1, Pages 2↔3):
- When SCROLL_X wraps from 639→0, viewport seamlessly continues from Page 1 back to Page 0
- Creates infinite horizontal scrolling: Page 0 → Page 1 → Page 0 → Page 1 → ...
- Same pattern for bottom row: Page 2 → Page 3 → Page 2 → Page 3 → ...

**Use Cases**:
- **Horizontal scrollers** (Mario): Use Pages 0-1 or Pages 2-3, CPU streams columns at right edge
- **Vertical scrollers**: Use Pages 0+2 or Pages 1+3 (wraps at Y=480)
- **Open world** (Zelda overworld): Use all 4 pages as 640×480 world, CPU streams edges
- **Zelda dungeons**: Disable scrolling (SCROLL_X=0, SCROLL_Y=0), use instant page switching for room transitions

#### Coordinate Mapping

**Logical Screen Coordinates** → **Tilemap Coordinates**:

```verilog
// Add scroll offset to screen position
scrolled_x = (pixel_x + SCROLL_X) % 640;
scrolled_y = (pixel_y + SCROLL_Y) % 480;

// Determine which page (0-3)
page_x = scrolled_x / 320;  // 0 or 1
page_y = scrolled_y / 240;  // 0 or 1
tilemap_page = page_y * 2 + page_x;  // 0,1,2,3

// Coordinates within selected page
tile_x = (scrolled_x % 320) / 8;  // 0-39
tile_y = (scrolled_y % 240) / 8;  // 0-29
```

**Example (SCROLL_X = 310, SCROLL_Y = 0)**:
- Left 10 pixels: From Page 0, columns 38-39
- Right 310 pixels: From Page 1, columns 0-38
- Viewport seamlessly spans both pages

#### Rendering Pipeline Integration

**Stage 1: Horizontal Blanking**
1. Calculate which pages will be visible on next scanline (based on SCROLL_Y)
2. If near page boundary, may need to fetch tiles from 2 pages (e.g., 35 tiles from Page 0, 5 tiles from Page 1)
3. Read up to 45 sprite indices and 6 priority bytes (5 bytes if single page, 6 if crossing boundary)
4. Perform sprite evaluation (unchanged)

**Stage 2: Active Scanline**
1. For each pixel, apply scroll offsets to determine source page and tile coordinates
2. Read sprite pixel data from pre-loaded buffers
3. Composite sprites with scrolled background
4. Output pixel value (doubled for VGA timing)

**Timing Impact**:
- Additional coordinate arithmetic fits within combinational logic (no extra clocks)
- May need 1 extra read during blanking when crossing page boundaries (45→46 reads worst case)
- Still fits comfortably in ~320 clock horizontal blanking budget

#### CPU Update Strategy

**For Horizontal Scrolling** (Mario-style):
1. CPU detects when SCROLL_X crosses an 8-pixel boundary
2. Calculates which column just scrolled off-screen (left edge)
3. Writes new column data to that position from compressed level data
4. Column wraps around and appears at right edge when viewport reaches it

**For Open World Scrolling** (Zelda overworld):
1. CPU maintains 2-tile border around visible area (as described in circular buffer technique)
2. Updates columns/rows at edges as player moves
3. Hardware scroll registers eliminate need for modulo arithmetic in rendering

**For Room Transitions** (Zelda dungeons):
1. Disable scrolling or keep at fixed positions (e.g., SCROLL_X=0, SCROLL_Y=0)
2. Use SetTilemapPage for instant room switches
3. Optional: Animate SCROLL_X/SCROLL_Y for smooth transitions between rooms

### Circular Buffer Scrolling (Alternative Software Technique)

**Note**: For games that don't need pixel-smooth scrolling, the existing 40×30 tilemap pages support NES/Dragon-Warrior-style seamless scrolling without using hardware scroll registers.

**Technique Overview**:
- **Visible area**: Configure smaller viewport (e.g., 36×26 tiles = 288×208 pixels)
- **Border margin**: 2-tile border on all edges (off-screen for tile updates)
- **CPU streaming**: Continuously write new tiles at edges as player moves
- **Coordinate wrapping**: Software implements `tile_x = (camera_x + pixel_x) % 40`, `tile_y = (camera_y + pixel_y) % 30`

**Benefits**:
- All 4 tilemap pages remain independent (different maps/levels)
- Simpler hardware (no scroll registers needed)
- Matches Dragon Warrior/NES RPG scrolling model

**Trade-off**: Movement snaps by tiles (8 pixels) instead of smooth pixel-by-pixel scrolling.

### Other Potential Hardware Additions
1. **Sprite scaling**: 2×2 tile sprites (16×16 pixels)
2. **Scanline effects**: Per-line X scroll for parallax
3. **Collision detection**: Hardware sprite-to-sprite collision flags

### SDRAM Integration (Future)
If SDRAM controller is integrated:
- Store additional sprite sheets in SDRAM (thousands of sprites)
- Larger tilemaps for scrolling worlds
- DMA transfers during vblank
- Animation frames pre-loaded

## Interrupt Support

### Interrupt Configuration

**Mode Control Register ($0000)**:
- Bits 0-4: Existing (mode, active page, working page, video active)
- **Bit 5: VBLANK interrupt enable** (0=disabled, 1=enabled)
- **Bit 6: Scanline interrupt enable** (0=disabled, 1=enabled)
- Bit 7: Reserved

**Status Register ($000F)** - Optimized for BIT instruction:
- **Bit 0: BUSY** (0=ready, 1=busy)
- **Bit 1: ERROR** (instruction error occurred)
- Bits 2-5: Reserved
- **Bit 6: VBLANK flag** (set at start of vertical blanking, cleared on read) → **V flag** via BIT
- **Bit 7: Scanline flag** (set when scanline reaches trigger value, cleared on read) → **N flag** via BIT

**Note**: Reading $000F clears both interrupt flags (bits 6 and 7). The BIT instruction is ideal for testing interrupt flags as bits 6 and 7 map directly to CPU V and N flags.

**Scanline Trigger (Internal Register)**:
- Set via **$2A SetScanline** instruction
- Range: 0-479 (physical VGA scanlines)
- Not directly CPU-addressable (uses instruction interface)

### Interrupt Behavior

**IRQ Output Pin:**
- Assert IRQ to 6502 when: `(VBLANK_flag && VBLANK_enable) || (Scanline_flag && Scanline_enable)`
- Remains asserted until CPU reads $000F (auto-clears flags)

**Vertical Blanking Interrupt:**
- Fires at start of vertical blanking period (~1.05ms duration)
- Safe time window for updating sprites, tilemap, palette
- Standard pattern used by NES, SNES, Genesis, Amiga

**Scanline Interrupt:**
- Fires after horizontal blanking completes at the scanline specified in SCANLINE_TRIGGER registers
- Triggers when physical VGA scanline counter equals SCANLINE_TRIGGER value (0-479)
- Allows mid-frame updates for advanced effects:
  - **Split-screen scrolling**: Change SCROLL_X/SCROLL_Y mid-frame (status bar vs playfield)
  - **Sprite multiplexing**: Move sprites to new positions for next screen region (C64 style)
  - **Parallax scrolling**: Different scroll speeds for different screen regions
  - **Raster effects**: Palette changes, mode switches per scanline

### Programming Notes

**Important:** When using interrupt mode, **do not poll $000F for BUSY/ERROR status**. Reading $000F clears the VBLANK/Scanline flags, which could cause missed interrupts.

**Recommended patterns:**

**Interrupt-driven with BIT instruction (preferred):**
```assembly
; Enable VBLANK interrupt
LDA $0000
ORA #$20      ; Set bit 5
STA $0000

; In IRQ handler:
IRQ_Handler:
  BIT $000F   ; Test status (clears interrupt flags)
              ; Bit 7 → N flag (Scanline)
              ; Bit 6 → V flag (VBLANK)

  BVS VBlankOccurred   ; Branch if V set (bit 6)
  RTI                  ; No VBLANK, spurious IRQ

VBlankOccurred:
  ; Update sprites during vblank
  JSR UpdateSprites
  RTI
```

**Scanline interrupt (split-screen scrolling example):**
```assembly
; Set scanline interrupt to trigger at scanline 160 (1/3 down screen)
LDA #160      ; Low byte
STA $0002
LDA #0        ; High byte
STA $0003
LDA #$2A      ; SetScanline instruction
STA $0001

; Enable both VBLANK and Scanline interrupts
LDA $0000
ORA #$60      ; Set bits 5 and 6
STA $0000

; In IRQ handler:
IRQ_Handler:
  BIT $000F   ; Test status (clears both interrupt flags)
              ; Bit 7 → N flag (Scanline)
              ; Bit 6 → V flag (VBLANK)

  BMI ScanlineInterrupt   ; Branch if N set (bit 7)
  BVS VBlankInterrupt     ; Branch if V set (bit 6)
  RTI                     ; Neither set, spurious IRQ

ScanlineInterrupt:
  ; Scanline 160 reached - change scroll for status bar
  LDA #0
  STA $0002
  STA $0003
  LDA #$27    ; SetScrollX = 0
  STA $0001

  LDA #0
  STA $0002
  STA $0003
  LDA #$28    ; SetScrollY = 0
  STA $0001

  BVC Done    ; If only scanline interrupt, done
  ; Fall through to handle VBLANK too if both set

VBlankInterrupt:
  ; VBLANK - restore scroll for playfield, update game state
  LDA GameScrollX
  STA $0002
  LDA GameScrollX+1
  STA $0003
  LDA #$27    ; SetScrollX
  STA $0001

  LDA GameScrollY
  STA $0002
  LDA GameScrollY+1
  STA $0003
  LDA #$28    ; SetScrollY
  STA $0001

  JSR UpdateSprites

Done:
  RTI
```

**Polling mode (if not using interrupts):**
```assembly
; Disable interrupts, poll VBLANK flag
LDA $0000
AND #$9F      ; Clear bits 5 and 6 (disable both interrupts)
STA $0000

WaitVBlank:
  BIT $000F   ; Test status (clears flags)
  BVS VBlankOccurred
  JMP WaitVBlank

VBlankOccurred:
  ; VBLANK occurred, update sprites
  JSR UpdateSprites
```

**Do NOT mix:** Don't enable interrupts and then poll $000F, as polling will clear interrupt flags and cause missed interrupts.

**BIT Instruction Benefits:**
- Single instruction reads and tests status register
- Bit 7 → N flag (Scanline interrupt)
- Bit 6 → V flag (VBLANK interrupt)
- Use BMI to test N flag, BVS to test V flag
- More efficient than LDA + AND + BEQ

### Timing Considerations

**VBLANK Window:**
- Duration: ~1.43ms (45 VGA blanking scanlines × 800 pixel clocks ÷ 25.175 MHz)
- At 1MHz CPU (PHI2): **~1,430 cycles available**
- Enough for: 128 sprite updates, tilemap changes, palette updates, page switches

**Typical VBLANK routine:**
1. Update sprite attributes (64 sprites × 10 cycles = ~640 cycles) - writes to registers, not VRAM
2. Update tilemap if needed (~200 cycles for moderate changes) - VRAM writes
3. Switch pages if needed (~10 cycles)
4. Palette updates (~50 cycles)
5. Exit (~20 cycles overhead)
6. **Total: ~920 cycles (plenty of headroom)**

**Note**: Sprite attribute updates can actually happen **anytime** (not just VBLANK) since they're stored in registers, not video RAM. VBLANK is only required for tilemap/sprite sheet updates.

## Sprite Priority System

### Priority Layers
The display is composited in the following order (front to back):
1. **Foreground tiles** (priority bit = 1)
2. **Sprites 0-7** (first-match-wins within sprites)
3. **Background tiles** (priority bit = 0)

### Sprite Priority Scheme
Sprites use **first-match-wins** priority based on sprite attribute table order:
- **Sprite 0**: Highest priority (always checked first)
- **Sprite 1**: Second priority
- **...continues through sprite 7**
- **Sprite 7**: Lowest priority (checked last)

### Priority Logic
```verilog
// Cascading priority chain (combinational logic)
always @(*) begin
    // Check foreground tiles first
    if (tile_priority && background_pixel != 0)
        final_color = background_pixel;
    // Then check sprites 0-7
    else if (sprite[0].pixel != 0 && sprite[0].x_match)
        final_color = sprite[0].pixel;
    else if (sprite[1].pixel != 0 && sprite[1].x_match)
        final_color = sprite[1].pixel;
    else if (sprite[2].pixel != 0 && sprite[2].x_match)
        final_color = sprite[2].pixel;
    else if (sprite[3].pixel != 0 && sprite[3].x_match)
        final_color = sprite[3].pixel;
    else if (sprite[4].pixel != 0 && sprite[4].x_match)
        final_color = sprite[4].pixel;
    else if (sprite[5].pixel != 0 && sprite[5].x_match)
        final_color = sprite[5].pixel;
    else if (sprite[6].pixel != 0 && sprite[6].x_match)
        final_color = sprite[6].pixel;
    else if (sprite[7].pixel != 0 && sprite[7].x_match)
        final_color = sprite[7].pixel;
    // Finally background tiles
    else
        final_color = background_pixel;
end
```

### Programmer Control
- **Static priority**: Sprite attribute table order determines priority
- **Dynamic priority**: CPU can reorder sprite attributes during VBLANK
- Want sprite in front? Move it earlier in attribute table
- Simple, deterministic, and matches NES/C64 behavior

### Transparency
- **Color 0 = transparent** for all sprites and tiles
- Transparent sprite pixels allow lower-priority sprites or background to show through
- Transparent background tiles would show black (or could be used for effects)
- Foreground tiles with color 0 are transparent (sprites/background show through)
- No alpha blending - simple on/off transparency

## Open Questions
1. Block transfer instruction design
2. Hardware scrolling implementation
3. Integration with existing mode switching logic
4. Scanline interrupt implementation details (if added later)

## Next Steps
1. Define exact memory map addresses
2. Design sprite compositor module architecture
3. Specify instruction timing and state machines
4. Create test bench for sprite rendering
5. Implement background tile renderer (adapt from text mode)
6. Implement moving sprite compositor
7. Add mode switching support to top-level module
