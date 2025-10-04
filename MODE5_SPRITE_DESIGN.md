# Mode 5: Sprite/Tile Graphics Mode - Design Document

## Overview
Mode 5 implements a sprite-based graphics system inspired by NES/retro game consoles, using existing video RAM for sprite storage and tilemap-based backgrounds.

## Display Configuration
- **Resolution**: 320×240 pixels
- **Color Depth**: 8 bits per pixel (64-color direct RGB, bypassing palette like Mode 4)
- **Background**: 40×30 tile grid (8×8 pixel tiles)
- **Moving Sprites**: Hardware sprite compositor with priority/transparency

## Memory Architecture

### Video RAM Layout (76,800 bytes total)
- **Sprite Sheet**: 256 sprites × 64 bytes = 16,384 bytes
  - Each sprite: 8×8 pixels × 8 bits/pixel = 64 bytes
  - Addressable with 8-bit sprite index (0-255)
  - 64-color palette using 6-bit RGB (like Mode 4)

- **Tilemap Pages**: 4 pages × 1,350 bytes = 5,400 bytes
  - Each page contains two planes:
    - **Sprite Index Plane**: 40×30 = 1,200 bytes (1 byte per tile)
    - **Priority Bit Plane**: 40×30 bits = 150 bytes (8 tiles per byte, packed)
  - Each sprite index byte: sprite pattern to use (0-255)
  - Each priority bit: 0=background (behind sprites), 1=foreground (in front of sprites)
  - Instant page switching for screen transitions

- **Sprite Attribute Table**: 256 bytes (128 sprites × 2 bytes minimum)
  - X position (9 bits) - supports 0-511 for smooth scrolling
  - Y position (8 bits) - supports 0-255
  - Sprite index (8 bits) - which sprite pattern to use
  - Flags (7 bits) - flip X/Y, priority, enable, etc.

- **Remaining**: ~55,016 bytes for:
  - Additional sprite sheet pages (~3 more 256-sprite sets)
  - Additional tilemap pages
  - Particle effects buffers
  - Scanline effect tables
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

**Two-Stage Pipeline:**

**Stage 1: Horizontal Blanking (~160 pixel clocks)**
1. Read 40 sprite indices from video RAM for next scanline's tiles
   - Address: `tilemap_base + (scanline_y / 8) * 40`
   - Store in 40-byte tile index buffer
2. Read 5 priority bytes (40 bits packed) from video RAM
   - Address: `tilemap_base + 1200 + (scanline_y / 8) * 5`
   - Store in 5-byte priority buffer (or unpack to 40-bit flags)
3. **Total: 45 reads** (fits easily in 160 clocks)

**Stage 2: Active Scanline (320 pixel clocks)**
1. Calculate which tile: `tile_num = pixel_x / 8` (0-39)
2. Read sprite index from buffer: `sprite_idx = tile_buffer[tile_num]`
3. Read priority flag from buffer: `priority = priority_buffer[tile_num]` or extract from packed byte
4. Calculate pixel offset within sprite: `offset = (scanline_y % 8) * 8 + (pixel_x % 8)`
5. **Single video RAM read**: `color = sprite_data[sprite_idx * 64 + offset]`
6. Pass background color + priority flag to compositor

**Key Design Points**:
- 40-byte tile index buffer uses ~320 flip-flops
- 5-byte priority buffer uses ~40 flip-flops (or 40 bits unpacked)
- Only 1 video RAM access per pixel clock ✓
- Video RAM Port A: CPU writes
- Video RAM Port B: Display reads (tilemap/priority during blanking, sprite pixels during active)

### Moving Sprite Rendering

**Stage 1: Horizontal Blanking (~160 pixel clocks)**
1. **Sprite Evaluation**:
   - Check all enabled sprites against next scanline Y position
   - Build list of active sprites for this scanline (up to 16-32 sprites)

2. **Sprite Line Buffer Loading**:
   - For each active sprite, read 8 pixels from video RAM
   - Store in sprite line buffers (8 bytes × 8 sprites = 64 bytes in flip-flops)
   - Calculate sprite data address: `sprite_data[sprite_idx * 64 + (scanline_y - sprite_y) * 8]`
   - 8 sprites × 8 reads = 64 reads
   - **Target: 8 sprites per scanline maximum**

**Stage 2: Active Scanline (320 pixel clocks)**
1. **Parallel Sprite Compositor**:
   - Background pixel from tile pipeline (from video RAM)
   - For each active sprite (0-7), check if X position overlaps current pixel
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

**Performance**:
- Background: 1 video RAM read per pixel (40 sprite indices + 5 priority bytes + 320 sprite pixels = 365 total reads per scanline)
- Moving sprites: Pre-loaded during blanking (64 reads for 8 sprites)
- **Total horizontal blanking: 109 reads (45 tilemap + 64 sprites) with 51 clocks spare**
- **8 sprites per scanline maximum** (matches NES capability)
- Total active sprites: 64-128 supported (evaluated each scanline, top 8 displayed)

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

### Sprite Attribute Table
- Base address: 0x5518 (after sprites + 4 tilemap pages: 0x4000 + 5400)
- Sprite N attributes: `0x5518 + (N * 4)` (if using 4 bytes per sprite)

## Instruction Set (Proposed)

### Sprite/Tile Instructions

#### $20 LoadSprite
**Description**: Write sprite pattern data to sprite sheet.

**Arguments**:
- `$0002`: Sprite index (0-255)
- `$0003`: Offset within sprite (0-63)
- `$0004`: Pixel data (8-bit color) - **Execute on update**

**Usage**: Write sprite data byte-by-byte, or implement block transfer

#### $21 SetTile
**Description**: Set background tilemap entry at X,Y position.

**Arguments**:
- `$0002`: Tile X position (0-39)
- `$0003`: Tile Y position (0-29)
- `$0004`: Sprite index to use (0-255)
- `$0005`: Priority bit (0=background, 1=foreground) - **Execute on update**

**Note**: Updates both sprite index plane and priority bit plane

#### $22 SetSpriteAttr
**Description**: Configure moving sprite attributes.

**Arguments**:
- `$0002`: Sprite number (0-127)
- `$0003`: X position
- `$0004`: Y position
- `$0005`: Sprite index
- `$0006`: Flags - **Execute on update**

#### $23 SetSpritePage
**Description**: Switch active sprite sheet page.

**Arguments**:
- `$0002`: Sprite page index (0-3) - **Execute on update**

#### $24 SetTilemapPage
**Description**: Switch active background tilemap page.

**Arguments**:
- `$0002`: Tilemap page index (0-3) - **Execute on update**

#### $25 LoadSpriteBlock (Optional - Hardware Acceleration)
**Description**: DMA-style block transfer for sprite loading.

**Arguments**:
- `$0002`: Sprite index (0-255)
- `$0003-$000A`: 64 bytes of sprite data
- **Execute on final byte**

## Hardware Implementation Notes

### Dual-Port BRAM Usage
- **Port A**: CPU interface (write sprite data, tilemap, attributes)
- **Port B**: Display rendering (read sprite pixels, tilemap)
- **Note**: Video RAM BSRAM already at 100% capacity (46/46 blocks used)

### Sprite Compositor Module
- Parallel to existing graphics_mode_module
- Shares video timing signals
- Outputs RGB when Mode 5 active
- Components:
  - Tile background renderer (reuse text mode logic)
  - 8 sprite line buffers (8 bytes each, implemented in flip-flops)
  - 8 parallel sprite comparators and pixel selectors
  - Priority compositor (blend sprites with background)

### Resource Requirements (Estimated)
- **Logic**: ~800 LUTs (4% of 20K available)
- **Registers**: ~800 flip-flops (5% of 15K available)
- **BSRAM**: 0 additional (sprite buffers use distributed RAM)
- **Total utilization**: ~12% logic, ~9% registers

### Performance Considerations
- **Background**: 320 pixels/scanline, just-in-time tile reads (proven in text mode)
- **Sprites**: 8 sprites/scanline maximum (matches NES capability)
- **Horizontal blanking budget**: 109 reads with 51 clocks spare
- **Total sprites**: 64-128 active sprites supported (top 8 per scanline displayed)
- **Pixel clock**: 25.175 MHz (same as existing modes)

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
- 64-128 total active sprites (vs 64)
- Per-tile foreground/background priority (NES had limited priority control)
- Flexible memory allocation
- 4 instant tilemap page switching

## Future Enhancements

### Potential Additions
1. **Hardware scrolling**: X/Y offset registers for tilemap
2. **Sprite scaling**: 2×2 tile sprites (16×16 pixels)
3. **Palette mode**: Use 4-bit pixels with 16-color palette for more sprites
4. **Scanline effects**: Per-line X scroll for parallax
5. **Collision detection**: Hardware sprite-to-sprite collision flags

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
1. Update sprite attribute table (64 sprites × 10 cycles = ~640 cycles)
2. Update tilemap if needed (~200 cycles for moderate changes)
3. Switch pages if needed (~10 cycles)
4. Palette updates (~50 cycles)
5. Exit (~20 cycles overhead)
6. **Total: ~920 cycles (plenty of headroom)**

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
