# Makefile for VGA Card Project Testing
# Requires iverilog and gtkwave

# Directory structure
SRC_DIR = src
TEST_DIR = tests

# Verilog source files (with paths)
SRC_SOURCES = $(SRC_DIR)/vga_timing.v $(SRC_DIR)/cpu_interface.v $(SRC_DIR)/text_mode_module.v $(SRC_DIR)/graphics_mode_module.v $(SRC_DIR)/vga_card.top.v
MEMORY_MODULE = $(SRC_DIR)/memory_modules.v

# Test executables
TESTS = test_vga_timing test_cpu_interface test_text_mode test_graphics_mode test_integration

# Default target
all: $(TESTS)

# VGA Timing Test
test_vga_timing: $(SRC_DIR)/vga_timing.v $(TEST_DIR)/tb_vga_timing.v
	iverilog -g2012 -o test_vga_timing -I$(SRC_DIR) -I$(TEST_DIR) $(SRC_DIR)/vga_timing.v $(TEST_DIR)/tb_vga_timing.v
	
run_vga_timing: test_vga_timing
	./test_vga_timing
	@echo "VGA timing test completed. Use 'make wave_vga_timing' to view waveforms."

wave_vga_timing: vga_timing.vcd
	gtkwave vga_timing.vcd &

# CPU Interface Test
test_cpu_interface: $(SRC_DIR)/cpu_interface.v $(TEST_DIR)/tb_cpu_interface.v
	iverilog -g2012 -o test_cpu_interface -I$(SRC_DIR) -I$(TEST_DIR) $(SRC_DIR)/cpu_interface.v $(TEST_DIR)/tb_cpu_interface.v
	
run_cpu_interface: test_cpu_interface
	./test_cpu_interface
	@echo "CPU interface test completed. Use 'make wave_cpu_interface' to view waveforms."

wave_cpu_interface: cpu_interface.vcd
	gtkwave cpu_interface.vcd &

# Text Mode Test (requires memory modules)
test_text_mode: $(SRC_DIR)/text_mode_module.v $(MEMORY_MODULE) $(TEST_DIR)/tb_text_mode.v
	iverilog -g2012 -o test_text_mode -I$(SRC_DIR) -I$(TEST_DIR) $(SRC_DIR)/text_mode_module.v $(MEMORY_MODULE) $(TEST_DIR)/tb_text_mode.v
	
run_text_mode: test_text_mode
	./test_text_mode
	@echo "Text mode test completed. Use 'make wave_text_mode' to view waveforms."

wave_text_mode: text_mode.vcd
	gtkwave text_mode.vcd &

# Graphics Mode Test (requires memory modules)
test_graphics_mode: $(SRC_DIR)/graphics_mode_module.v $(MEMORY_MODULE) $(TEST_DIR)/tb_graphics_mode.v
	iverilog -g2012 -o test_graphics_mode -I$(SRC_DIR) -I$(TEST_DIR) $(SRC_DIR)/graphics_mode_module.v $(MEMORY_MODULE) $(TEST_DIR)/tb_graphics_mode.v
	
run_graphics_mode: test_graphics_mode
	./test_graphics_mode
	@echo "Graphics mode test completed. Use 'make wave_graphics_mode' to view waveforms."

wave_graphics_mode: graphics_mode.vcd
	gtkwave graphics_mode.vcd &

# Integration Test
test_integration: $(SRC_SOURCES) $(MEMORY_MODULE) $(TEST_DIR)/tb_integration.v
	iverilog -g2012 -o test_integration -I$(SRC_DIR) -I$(TEST_DIR) $(SRC_SOURCES) $(MEMORY_MODULE) $(TEST_DIR)/tb_integration.v
	
run_integration: test_integration
	./test_integration
	@echo "Integration test completed. Use 'make wave_integration' to view waveforms."

wave_integration: integration.vcd
	gtkwave integration.vcd &

# Clean up
clean:
	rm -f $(TESTS) *.vcd *.lxt

# Run all tests
test_all: run_vga_timing run_cpu_interface run_text_mode run_graphics_mode run_integration
	@echo "All tests completed successfully!"

# Quick syntax check
syntax_check:
	@echo "Checking syntax of all modules..."
	iverilog -g2012 -t null -I$(SRC_DIR) $(SRC_SOURCES) $(MEMORY_MODULE)
	@echo "Syntax check completed."

.PHONY: all clean test_all syntax_check
.SECONDARY: # Prevent deletion of intermediate files