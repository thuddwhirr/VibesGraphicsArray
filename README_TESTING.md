# VGA Card Testing Guide

This document describes the incremental testing approach for the VGA card project using iverilog.

## Prerequisites

- `iverilog` (Icarus Verilog simulator)
- `gtkwave` (waveform viewer) - optional but recommended
- `make` utility

## Test Structure

### Phase 1: Individual Module Testing

#### 1. VGA Timing Module Test
```bash
make run_vga_timing
```
**Tests:**
- Counter operation (hcount, vcount)
- Sync signal generation (hsync, vsync) 
- Display area detection
- Frame rate verification (~60Hz)
- Reset functionality

**Expected Results:**
- Frame rate: 59.4-60.6 Hz
- hcount: 0-799, vcount: 0-524
- hsync/vsync negative polarity timing

#### 2. CPU Interface Test
```bash  
make run_cpu_interface
```
**Tests:**
- Register read/write operations
- PHI2 timing compliance
- Instruction triggering mechanism
- Status register functionality
- Error handling
- Chip enable logic

**Expected Results:**
- All register values read back correctly
- instruction_start pulse on execute register write
- Proper busy/ready status indication

### Phase 2: Mode-Specific Testing

#### 3. Text Mode Module Test
```bash
make run_text_mode
```
**Tests:**
- Character writing and cursor advancement
- Scrolling behavior
- Text positioning
- Character attribute handling
- Font rendering pipeline

#### 4. Graphics Mode Module Test  
```bash
make run_graphics_mode
```
**Tests:**
- Pixel writing in different modes
- Read-modify-write operations
- Mode parameter calculation
- Cursor positioning
- Screen clearing

### Phase 3: Integration Testing

#### 5. Full System Test
```bash
make run_integration
```
**Tests:**
- Mode switching between text/graphics
- CPU interface with all modules
- Memory arbitration
- Video output generation
- Complete instruction sequences

## Running Tests

### Quick Start
```bash
# Run all tests sequentially
make test_all

# Check syntax only
make syntax_check

# Clean up generated files
make clean
```

### Individual Test Execution
```bash
# Compile and run specific test
make run_vga_timing

# View waveforms (requires gtkwave)
make wave_vga_timing
```

### Debug Process

1. **Syntax Errors**: Use `make syntax_check` first
2. **Simulation Failures**: Check console output for ASSERTION FAILED messages
3. **Timing Issues**: Use gtkwave to examine signal relationships
4. **Logic Errors**: Add $display statements and re-run

### Waveform Analysis

Key signals to monitor:

**VGA Timing:**
- `video_clk`, `hcount`, `vcount`
- `hsync`, `vsync`, `display_active`

**CPU Interface:**  
- `phi2`, `addr`, `data_bus`, `rw`
- `instruction_start`, `instruction_busy`
- Register values in `uut.registers`

**Text/Graphics Modes:**
- State machine states
- Memory addresses and data
- Instruction execution flow

## Test Development Guidelines

### Adding New Tests

1. Create testbench file: `tb_<module_name>.v`
2. Use common utilities from `test_common.vh`
3. Include comprehensive assertions
4. Add timeout protection
5. Update Makefile with new targets

### Best Practices

- **Use meaningful test names** and section comments
- **Test edge cases** and error conditions  
- **Verify timing relationships** not just logic
- **Include reset testing** in all modules
- **Add assertions liberally** with descriptive messages

### Common Issues

- **Clock domain crossings**: Ensure proper synchronization
- **Bus timing**: PHI2 setup/hold times critical
- **Memory initialization**: BRAM may need explicit initialization
- **Tristate conflicts**: Check bus driver enables

## Expected Test Results

All tests should complete with "tests passed" messages. Typical run times:

- VGA Timing: ~10-20 seconds (simulates multiple frames)
- CPU Interface: ~5-10 seconds  
- Text Mode: ~15-30 seconds (tests scrolling)
- Graphics Mode: ~20-40 seconds (tests all modes)
- Integration: ~60-120 seconds (full system test)

## Next Steps After Testing

1. **Synthesis Testing**: Verify design fits Tang Nano-20k resources
2. **Timing Analysis**: Check setup/hold time constraints
3. **Hardware Validation**: Test on actual Tang Nano-20k board
4. **Performance Optimization**: Address any timing violations

## Troubleshooting

### Simulation Hangs
- Check for infinite loops in state machines
- Verify clock generation in testbenches
- Ensure timeout protection is enabled

### Memory Errors
- Check if memory modules are included in compilation
- Verify address ranges don't exceed memory bounds
- Ensure proper initialization of memory instances

### Timing Mismatches
- Verify clock frequencies in testbenches match design
- Check setup/hold times for bus operations
- Ensure proper edge triggering in always blocks