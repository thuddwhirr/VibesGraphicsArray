# VGA Card Project - Quick Start Guide

## 🚀 Run All Tests

The easiest way to validate your VGA card design:

```bash
./run_tests.sh
```

This runs the complete test suite and provides a summary of results.

## 🔧 Individual Tests

If you prefer to run tests individually:

```bash
# Check syntax first
make syntax_check

# Basic module tests
make run_vga_timing        # Test VGA timing generation
make run_cpu_interface     # Test 65C02 bus interface

# Mode-specific tests  
make run_text_mode         # Test text mode functionality
make run_graphics_mode     # Test graphics modes

# Full system test
make run_integration       # Test complete system
```

## 👀 View Waveforms

After running tests, view timing diagrams with gtkwave:

```bash
make wave_vga_timing       # VGA timing waveforms
make wave_cpu_interface    # CPU bus timing
make wave_integration      # Full system signals
```

## 🐛 Debugging Failed Tests

1. **Check console output** for ASSERTION FAILED messages
2. **Review log files** (e.g., `vga_timing.log`, `cpu_interface.log`)
3. **Open waveform files** to examine signal timing
4. **Look for syntax errors** in `syntax_check.log`

## 📋 Expected Results

✅ **All tests should pass** with messages like:
- "VGA timing test passed!"
- "CPU interface test passed!"
- "Integration test completed successfully!"

❌ **Common issues:**
- **Font file missing**: Ensure `font_8x16.mem` exists
- **Timing violations**: Check clock domain crossings
- **Memory initialization**: Verify BRAM setup

## 🏗️ Next Steps After Testing

1. **Hardware Setup**:
   - Prepare level shifter board (5V ↔ 3.3V)
   - Design VGA DAC with voltage dividers
   - Plan Tang Nano-20k pin assignments

2. **FPGA Implementation**:
   - Synthesize with Gowin EDA
   - Check resource utilization (should use ~83% BRAM)
   - Verify timing constraints

3. **Hardware Testing**:
   - Program Tang Nano-20k
   - Connect to 65C02 system via level shifters
   - Test VGA output on monitor

## 🎯 Success Criteria

Your design is ready for hardware when:
- ✅ All simulation tests pass
- ✅ Synthesis completes without critical warnings  
- ✅ Resource utilization fits Tang Nano-20k (20K LUTs, 46 BRAM blocks)
- ✅ Timing analysis shows no violations

## 🔗 Files Overview

- `run_tests.sh` - Complete test suite runner
- `Makefile` - Individual test targets
- `test_common.vh` - Shared test utilities
- `tb_*.v` - Individual testbenches
- `README_TESTING.md` - Detailed testing guide

Ready to test your VGA card design! 🎮