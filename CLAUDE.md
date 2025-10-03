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

## Next Steps
1. Consider implementing text editor block operations:
   - TEXT_WRITE_AT for direct positioning writes
   - TEXT_BLOCK_FILL for efficient region clearing
   - SCROLL_UP/SCROLL_DOWN for viewport control
2. Develop test applications to further validate CLI behavior