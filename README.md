# VGA Card Project

A complete EGA/VGA-style video card implementation for Tang Nano-20k FPGA with 65C02 CPU interface.

## Directory Structure

```
├── src/                    # Source code
│   ├── vga_timing.v       # VGA timing generator (640×480@60Hz)
│   ├── cpu_interface.v    # 65C02 bus interface with continuous latch design
│   ├── text_mode_module.v # Text mode controller (80×30 display)
│   ├── graphics_mode_module.v # Graphics mode controller (4 modes)
│   ├── memory_modules.v   # BRAM modules (character buffer, video memory, font ROM, palette)
│   └── vga_card.top.v    # Top-level integration module
├── tests/                 # Test benches and verification
│   ├── tb_vga_timing.v   # VGA timing verification
│   ├── tb_cpu_interface.v # CPU bus interface tests
│   ├── tb_text_mode.v    # Text mode instruction tests
│   ├── tb_graphics_mode.v # Graphics mode bit packing tests
│   ├── tb_integration.v  # Full system integration tests
│   └── test_common.vh    # Common test utilities and macros
├── Makefile              # Build system for all tests
└── specification.md      # Complete hardware specification
```

## Features

### Text Mode
- 80×30 character display with 8×16 pixel fonts
- Hardware scrolling
- 16 foreground/background color combinations
- Instructions: TextWrite, TextPosition, TextClear, GetTextAt

### Graphics Modes
- Mode 1: 640×480×2 colors (1 bit/pixel, 8 pixels/byte, 2 pages)
- Mode 2: 640×480×4 colors (2 bits/pixel, 4 pixels/byte, 1 page)  
- Mode 3: 320×240×16 colors (4 bits/pixel, 2 pixels/byte, 2 pages)
- Mode 4: 320×240×64 colors (8 bits/pixel, 1 pixel/byte, 1 page)
- Instructions: WritePixel, PixelPosition, WritePixelPos, ClearScreen, GetPixelAt

### Hardware Features
- Dual-domain design: 1MHz CPU ↔ 25.175MHz video
- Proper address multiplexing between controller and display renderer
- Multi-cycle memory operations for reliable BRAM access
- Continuous latch CPU interface for reliable 65C02 writes
- Level shifting support for 3.3V FPGA ↔ 5V CPU

## Building and Testing

### Prerequisites
- iverilog (Icarus Verilog)
- gtkwave (for waveform viewing)
- make

### Quick Start
```bash
# Run all tests
make test_all

# Run individual tests
make run_vga_timing
make run_cpu_interface  
make run_text_mode
make run_graphics_mode
make run_integration

# Check syntax of all modules
make syntax_check

# View waveforms (after running tests)
make wave_graphics_mode
```

### Test Coverage
- **VGA Timing**: Verifies 640×480@60Hz signal generation (59.94Hz actual)
- **CPU Interface**: Tests register read/write operations and instruction flow
- **Text Mode**: Comprehensive testing of all 4 text instructions with timing validation
- **Graphics Mode**: Bit packing/unpacking validation for all 4 graphics modes
- **Integration**: Full system test combining CPU operations with video generation

## Key Technical Insights

### Timing Considerations
The system operates across two clock domains:
- CPU domain: 1MHz PHI2 clock
- Video domain: 25.175MHz pixel clock

This 25:1 ratio requires careful timing margins for memory operations. Key lessons learned:

1. **Multi-cycle memory reads**: BRAM requires 2-3 cycles for reliable data after address changes
2. **Address multiplexing**: Display renderer and controller need separate address control
3. **Instruction completion delays**: Allow 50-100 cycles for cross-domain operations

### BRAM Access Patterns
- **Controller**: Uses port A for read/write operations during instruction execution
- **Display Renderer**: Uses port B for continuous video memory reads
- **Address multiplexing**: Controller gets priority during active operations

### 65C02 Interface Design
Uses "continuous latch" approach where write operations occur on combinational logic rather than clocked logic, improving reliability with the 65C02's bus timing characteristics.

## Hardware Compatibility
- **Primary Target**: Tang Nano-20k (Gowin GW2AR-18 FPGA)
- **CPU Interface**: WDC 65C02 with PHI2 clock
- **Video Output**: Standard VGA (requires external level shifters and DAC)
- **Memory**: Uses FPGA BRAM (no external memory required)

## Status
✅ **Complete and tested** - All core functionality implemented and verified
- VGA timing generation
- Text mode with all instructions
- Graphics modes with bit packing
- CPU interface with proper timing
- Cross-domain memory operations
- Full system integration

Ready for FPGA synthesis and hardware testing.