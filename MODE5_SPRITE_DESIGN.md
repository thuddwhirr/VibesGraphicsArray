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
- Requires 12-bit RGB DAC hardware (4 bits per color channel via R-2R networks)
- Current 6-bit RGB (2-2-2) hardware must be upgraded first

**Status**: Design complete, pending 12-bit color hardware implementation.

### Other Potential Additions
1. **Hardware scrolling**: X/Y offset registers for tilemap
2. **Sprite scaling**: 2×2 tile sprites (16×16 pixels)
3. **Scanline effects**: Per-line X scroll for parallax
4. **Collision detection**: Hardware sprite-to-sprite collision flags

### SDRAM Integration (Future)
If SDRAM controller is integrated:
- Store additional sprite sheets in SDRAM (thousands of sprites)
- Larger tilemaps for scrolling worlds
- DMA transfers during vblank
- Animation frames pre-loaded

## Interrupt Support

### Interrupt Configuration

**Mode Control Register ($0000)** - Extended bits:
- Bits 0-4: Existing (mode, active page, working page, video active)
- **Bit 5: VBLANK interrupt enable** (0=disabled, 1=enabled)
- **Bit 6: Scanline interrupt enable** (0=disabled, 1=enabled) - reserved for future

**Status Register ($000F)** - Extended bits:
- Bit 0: BUSY (existing)
- Bit 1: ERROR (existing)
- **Bit 3: VBLANK flag** (set by hardware at start of vertical blanking, cleared on read)
- **Bit 4: Scanline flag** (reserved for future - set at specific scanline)
- Bit 7: READY (existing)

### Interrupt Behavior

**IRQ Output Pin:**
- Assert IRQ to 6502 when: `(VBLANK_flag && VBLANK_enable) || (Scanline_flag && Scanline_enable)`
- Remains asserted until CPU reads $000F (auto-clears flags)

**Vertical Blanking Interrupt:**
- Fires at start of vertical blanking period (~1.05ms duration)
- Safe time window for updating sprites, tilemap, palette
- Standard pattern used by NES, SNES, Genesis, Amiga

**Scanline Interrupt (Future):**
- Would fire after horizontal blanking completes (after sprite buffers loaded)
- Allows mid-frame sprite updates for multiplexing effects (C64 style)
- CPU could update sprite attributes for scanline N+2

### Programming Notes

**Important:** When using interrupt mode, **do not poll $000F for BUSY/ERROR status**. Reading $000F clears the VBLANK/Scanline flags, which could cause missed interrupts.

**Recommended patterns:**

**Interrupt-driven (preferred):**
```assembly
; Enable VBLANK interrupt
LDA $0000
ORA #$20      ; Set bit 5
STA $0000

; In IRQ handler:
IRQ_Handler:
  LDA $000F   ; Read status (clears VBLANK flag, deasserts IRQ)
  AND #$08    ; Check bit 3
  BEQ NotVBlank

  ; Update sprites during vblank
  JSR UpdateSprites

NotVBlank:
  RTI
```

**Polling mode (if not using interrupts):**
```assembly
; Disable interrupts, poll VBLANK flag
LDA $0000
AND #$DF      ; Clear bit 5
STA $0000

WaitVBlank:
  LDA $000F
  AND #$08    ; Check VBLANK flag
  BEQ WaitVBlank

  ; VBLANK occurred, update sprites
  JSR UpdateSprites
```

**Do NOT mix:** Don't enable interrupts and then poll $000F, as the polling will clear interrupt flags.

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
