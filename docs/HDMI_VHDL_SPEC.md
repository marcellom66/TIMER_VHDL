# HDMI_VHDL Specification

## Purpose

This document provides a maintenance-oriented technical specification for the `HDMI_VHDL` project.
The structure is inspired by formal military and industrial documentation styles, including STANAG-like sectioning, but it is not an official NATO compliance artifact.

## System Scope

The design generates an HDMI-compatible TMDS stream for the TangNano-20K platform.
Included functions:

- clock generation and conditioning
- user input decoding through a push-button
- selectable video test patterns
- on-screen `HH:MM:SS` clock overlay
- optional real-time clock synchronization through UART RX
- TMDS encoding and differential output through Gowin IP

## Top-Level Integration

Primary integration module:

- `src/video_top.vhd`

Responsibilities:

- derive internal resets from the external reset and PLL lock
- instantiate the PLL and clock divider
- acquire user pattern selection from `key_led_ctrl`
- request a video raster from `testpattern`
- feed RGB and sync signals into `DVI_TX_Top`

## Clock Architecture

Reference input:

- `I_clk`

Internal clocks:

- `serial_clk`: high-speed clock for the HDMI/DVI transmitter
- `pix_clk`: pixel-domain clock for video timing and user logic

Clock generation chain:

1. `tmds_rpll` receives `I_clk`
2. the Gowin `rPLL` generates `serial_clk`
3. `CLKDIV` derives `pix_clk` from `serial_clk`

## Reset Strategy

External reset:

- `I_rst` is active high

Derived resets:

- `rst_n = not I_rst`
- `hdmi_rst_n = rst_n and pll_lock`

Rationale:

- blocks related to HDMI transmission are released only after PLL lock is valid
- this avoids unstable startup timing at the TMDS encoder boundary

## Video Format

Current implemented format:

- `1280x720 @ 60 Hz`

Timing model:

- total horizontal pixels: `1650`
- total vertical lines: `750`
- horizontal sync width: `40`
- vertical sync width: `5`
- horizontal back porch: `220`
- vertical back porch: `20`

Implementation location:

- `src/testpattern.vhd`

## Pattern Generator

Pattern selector input:

- `I_pat_sel(2 downto 0)`

Implemented modes:

- `000`: color bars
- `001`: red grid on black background
- `010`: grayscale gradient
- `011`: full blue
- `100`: full green
- `101`: full red
- `110`: full white

## Clock Overlay

Display format:

- `HH:MM:SS`

Characteristics:

- bitmap font provided by `src/clock_font_pkg.vhd`
- the package can be regenerated from a TTF using `tools/ttf_to_vhdl_font.py`
- rounded rectangular background panel
- softened border and corner blending through discrete coverage levels
- optional serial time load if a valid UART frame is received

Time base:

- one second is derived by counting `60` video frames

Limitations:

- the overlay is not backed by a real-time clock peripheral
- after reset, the display restarts from `00:00:00`
- if no valid serial frame is received, the clock continues using the internal frame counter

UART time synchronization:

- top-level pin: `I_uart_rx`
- board pin assignment: `70`
- electrical level: `3.3 V LVCMOS`
- UART mode: `115200 8N1`
- on the onboard Tang Nano 20K debugger, channel `8209` is typically JTAG and channel `8210` is the UART endpoint
- accepted frame format: `HH:MM:SS` followed by `CR` or `LF`
- optional alternate frame format: `THH:MM:SS` followed by `CR` or `LF`
- helper script: `tools/send_time.py`
- helper script supports either an OS serial device path or direct `pyftdi` access to the onboard debugger UART channel
- `pyftdi` direct URL for the Tang Nano 20K UART is typically `ftdi://ftdi:2232h/2`
- specific-board `pyftdi` URL example: `ftdi://ftdi:2232h:2023030621/2`
- font generation helper: `tools/ttf_to_vhdl_font.py`

Host-side helper examples:

- `python3 tools/send_time.py /dev/tty.usbserial-0001`
- `python3 tools/send_time.py /dev/tty.usbserial-0001 --watch --interval 1`
- `python3 tools/send_time.py /dev/tty.usbserial-0001 --time 12:34:56`
- `python3 tools/send_time.py COM5 --prefix-t`
- `python3 tools/send_time.py ftdi://ftdi:2232h/2 --verbose`
- `python3 tools/send_time.py --tang-uart --ftdi-serial 2023030621 --verbose`

## User Interface Logic

Module:

- `src/key_led_ctrl.vhd`

Responsibilities:

- synchronize push-button input
- debounce mechanical transitions
- increment pattern selection counter
- drive active-low board LEDs

## Vendor-Specific Dependencies

The project depends on Gowin-specific primitives and IP:

- `rPLL`
- `CLKDIV`
- `DVI_TX_Top`

Portability note:

- these blocks are not portable generic VHDL components and tie the project to the Gowin toolchain and target family unless replaced

## Maintenance Notes

When modifying the design, review all of the following together:

- `src/video_top.vhd`
- `src/testpattern.vhd`
- `src/tmds_rpll.vhd`
- `src/nano_20k_video.sdc`
- `src/hdmi.cst`

Changes to clock ratios, resolution, or porch timing require consistency across:

- RTL timing constants
- PLL and divider configuration
- synthesis and timing constraints
- monitor compatibility expectations
