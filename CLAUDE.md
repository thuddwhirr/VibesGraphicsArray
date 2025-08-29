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

### Performance Analysis
**Problem**: 1MHz CPU may be too slow for full screen redraws needed by text editors
- Full screen = 2,400 characters × 2 instructions = 4,800+ cycles  
- Estimated 10-20ms for complete redraw - too slow for responsive editing

**Solution**: Add hardware-accelerated block operations

## Planned Enhancements

### New Text Mode Instructions
1. **TEXT_WRITE_AT (0x04)**: Write character directly at specified position (no separate positioning)
2. **TEXT_BLOCK_COPY (0x05)**: Hardware-accelerated rectangle copying
3. **TEXT_BLOCK_FILL (0x06)**: Fill rectangle with character/attributes
4. **TEXT_SCROLL_REGION (0x07)**: Scroll only part of screen

### Benefits
- **Text editors**: Efficient page up/down using block copy instead of full redraw
- **Insert/delete lines**: Scroll region operations  
- **Status bars**: Partial screen updates
- **Menus**: Block fill for backgrounds

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
- `src/text_mode_module.v` - Main text mode implementation
- `tests/tb_text_mode.v` - Test bench
- `font_8x16.mem` - 8×16 font ROM data (Code Page 437)

## Next Steps
Implement the new block operation instructions to enable efficient text editor operations while maintaining the current TTY-style interface for simple applications.