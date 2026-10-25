create_clock -name ref_clk -period 20.000 [get_ports {clk}]
create_generated_clock -name mid_clk -source [get_ports {clk}] -multiply_by 16 -divide_by 25 [get_pins {clocks/pll1/CLKOUT0}]
create_generated_clock -name audio_clk -source [get_pins {clocks/pll1/CLKOUT0}] -multiply_by 48 -divide_by 25 [get_pins {clocks/pll2/CLKOUT0}]
# Bound external MAX98357A audio output paths to 0..30 ns, including implementation
# clock insertion. No generated clock is placed on the BCK DATA net: Gowin
# otherwise propagates that clock into BCK's counter/CE fanout.
# BCK and WS/DIN change on the SAME source edge; the receiving edge is 20
# audio cycles later (325.52 ns). Thus this bound leaves at least 295.52 ns
# nominal setup/hold spacing before board skew, to be measured on hardware.
# 30 ns is a deliberate route budget, NOT a MAX98357A datasheet timing limit.
# SD_MODE clocked enable is covered too; shutdown remains asynchronous.
# Board skew, receiver timing and physical voltage still need user verification.
# No audio paths are false-pathed or granted an unproven multicycle exception.
set_max_delay -from [get_clocks {audio_clk}] -to [get_ports {MAX_BCLK MAX_LRCLK MAX_DIN MAX_SD_MODE}] 30.000
set_min_delay -from [get_clocks {audio_clk}] -to [get_ports {MAX_BCLK MAX_LRCLK MAX_DIN MAX_SD_MODE}] 0.000
# rst is an asynchronous button, not a synchronous data input. No fake
# input arrival time is imposed; its reset synchronizer is checked by TB.

# Open-drain column enable paths; row inputs are asynchronous and two-flop synchronized.
set_max_delay -from [get_clocks {audio_clk}] -to [get_ports {key_col[0] key_col[1] key_col[2] key_col[3]}] 30.000
set_min_delay -from [get_clocks {audio_clk}] -to [get_ports {key_col[0] key_col[1] key_col[2] key_col[3]}] 0.000

# Human-visible LEDs: deliberate 100ns output-route budget, no audio timing exception.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4] led_n[5]}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4] led_n[5]}] 0.000

# Default LCD profile: 35 MHz; forwarded PCLK inverted at lcd_clk.
# Model the REAL sampling clock at the connector, including its routed delay.
# Old 6 ns clock-to-port max_delay also counted PLL/clock insertion (8.594 ns
# in the uploaded report), making the intended route budget unattainable.
# A half-period is 14.286 ns. Reserving 8.286 ns before the sampling edge
# reproduces a nominal 6 ns data-path budget at zero clock/data skew.
# The min value checks non-negative hold margin. These are ENGINEERING
# margins, not certified panel tSU/tH; board skew/panel datasheet still needed.
# All internal ref/audio/pixel periods stay unchanged; no data-path exceptions.
# This profile is for LCD_ENABLE=1 and LCD_PCLK_INVERT=1.
create_generated_clock -name pixel_clk -source [get_ports {clk}] -multiply_by 7 -divide_by 10 [get_pins {lcd_on.display_driver/pixel_pll/CLKOUT0}]
create_generated_clock -name lcd_pclk -source [get_pins {lcd_on.display_driver/pixel_pll/CLKOUT0}] -divide_by 1 -invert [get_ports {lcd_clk}]
set_output_delay -clock lcd_pclk -max 8.286 [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}]
set_output_delay -clock lcd_pclk -min 0.000 [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}]

# Touch controller is entirely in ref_clk; SCL is registered open-drain data,
# never an internal clock. Inputs pass through two registers inside the master.
# 100ns is an implementation route budget versus 5us nominal half-period,
# not a substitute for measuring pull-up rise time or panel IO voltage.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {touch_scl touch_sda touch_int touch_rst_n}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {touch_scl touch_sda touch_int touch_rst_n}] 0.000

# Genuine asynchronous reset-synchronizer ENTRY pins only (four endpoints).
# These PRESET inputs may deassert at any phase; reset_sync holds ones while
# shifting zero over two destination clocks. Its output-to-consumer reset
# recovery/removal, its D/Q paths, and all ordinary data paths remain timed.
# Explicit names from the uploaded netlist; verify all FOUR match after synthesis.
# Do not replace with whole-register/whole-clock false paths.
set_false_path -to [get_pins {lcd_on.display_driver/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/pixel_reset_sync/pipe_1_s0/PRESET lcd_on.display_driver/status_bridge/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/status_bridge/pixel_reset_sync/pipe_1_s0/PRESET}]

# Keep each internal domain visible even when global worst paths are I/O.
report_timing -setup -from [get_clocks {ref_clk}] -to [get_clocks {ref_clk}] -max_paths 10
report_timing -setup -from [get_clocks {audio_clk}] -to [get_clocks {audio_clk}] -max_paths 10
report_timing -setup -from [get_clocks {pixel_clk}] -to [get_clocks {pixel_clk}] -max_paths 10
