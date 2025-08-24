# Tang Nano-20k Synthesis Check Script for Gowin EDA
# This script performs synthesis and resource utilization analysis

# Set device parameters for Tang Nano-20k
set_device GW2AR-LV18QN88C8/I7

# Add source files
add_file vga_card.top.v
add_file cpu_interface.v
add_file vga_timing.v
add_file text_mode_module.v
add_file graphics_mode_module.v
add_file memory_modules.v

# Set top-level module
set_option -top_module vga_card_top

# Set synthesis options
set_option -include_path .
set_option -verilog_std sysv2017
set_option -use_dsp_for_mult yes
set_option -use_bram_for_large_mux yes

# Clock constraints
create_clock -name clk_25mhz -period 39.72 [get_ports clk_25mhz]
create_clock -name phi2 -period 1000 [get_ports phi2]

# Set clock groups (asynchronous)
set_clock_groups -asynchronous -group [get_clocks clk_25mhz] -group [get_clocks phi2]

# I/O constraints for Tang Nano-20k pinout
# Note: These are example pins - adjust based on actual board connections

# System clocks
set_property -dict {PACKAGE_PIN N11} [get_ports clk_25mhz]
set_property -dict {PACKAGE_PIN P1} [get_ports phi2]
set_property -dict {PACKAGE_PIN P2} [get_ports reset_n]

# 65C02 Bus Interface (GPIO pins)
set_property -dict {PACKAGE_PIN T2} [get_ports {addr[0]}]
set_property -dict {PACKAGE_PIN T3} [get_ports {addr[1]}]
set_property -dict {PACKAGE_PIN U1} [get_ports {addr[2]}]
set_property -dict {PACKAGE_PIN U2} [get_ports {addr[3]}]

set_property -dict {PACKAGE_PIN R1} [get_ports {data[0]}]
set_property -dict {PACKAGE_PIN R2} [get_ports {data[1]}]
set_property -dict {PACKAGE_PIN R3} [get_ports {data[2]}]
set_property -dict {PACKAGE_PIN T4} [get_ports {data[3]}]
set_property -dict {PACKAGE_PIN T5} [get_ports {data[4]}]
set_property -dict {PACKAGE_PIN T6} [get_ports {data[5]}]
set_property -dict {PACKAGE_PIN U3} [get_ports {data[6]}]
set_property -dict {PACKAGE_PIN U4} [get_ports {data[7]}]

set_property -dict {PACKAGE_PIN V1} [get_ports rw]
set_property -dict {PACKAGE_PIN V2} [get_ports ce0]
set_property -dict {PACKAGE_PIN V3} [get_ports ce1b]

# VGA Output pins
set_property -dict {PACKAGE_PIN B1} [get_ports {red[0]}]
set_property -dict {PACKAGE_PIN B2} [get_ports {red[1]}]
set_property -dict {PACKAGE_PIN C1} [get_ports {green[0]}]
set_property -dict {PACKAGE_PIN C2} [get_ports {green[1]}]
set_property -dict {PACKAGE_PIN D1} [get_ports {blue[0]}]
set_property -dict {PACKAGE_PIN D2} [get_ports {blue[1]}]
set_property -dict {PACKAGE_PIN A1} [get_ports hsync]
set_property -dict {PACKAGE_PIN A2} [get_ports vsync]

# Set I/O standards
set_property IOSTANDARD LVCMOS33 [get_ports -filter {DIRECTION == INPUT}]
set_property IOSTANDARD LVCMOS33 [get_ports -filter {DIRECTION == OUTPUT}]
set_property IOSTANDARD LVCMOS33 [get_ports -filter {DIRECTION == INOUT}]

# Run synthesis
run_syn

# Generate reports
report_timing -max_paths 100 -file timing_report.txt
report_utilization -file utilization_report.txt
report_power -file power_report.txt

# Check for critical warnings and errors
if {[get_msg_config -severity ERROR -count] > 0} {
    puts "ERROR: Synthesis failed with errors!"
    exit 1
}

if {[get_msg_config -severity CRITICAL_WARNING -count] > 0} {
    puts "WARNING: Synthesis completed with critical warnings!"
}

puts "Synthesis completed successfully!"
puts "Check reports: timing_report.txt, utilization_report.txt, power_report.txt"