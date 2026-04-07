//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
create_clock -name pix_clk -period 13.468 -waveform {0 6.734} [get_pins {U_clkdiv/CLKOUT}]
create_clock -name I_clk -period 37.037 -waveform {0 18.518} [get_ports {I_clk}] -add
