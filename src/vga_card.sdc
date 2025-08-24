//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.9 Beta-4 Education
//Created Time: 2025-07-28 12:07:37
create_clock -name CPU_clock -period 1000 -waveform {0 500} [get_ports {phi2}]
create_clock -name VGA_clock -period 39.722 -waveform {0 19.861} [get_ports {clk_25mhz}]

# Mark clocks as independent - simpler syntax for Gowin
set_clock_groups -asynchronous -group CPU_clock -group VGA_clock
