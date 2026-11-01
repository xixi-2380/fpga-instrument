create_clock -name ref_clk -period 20.000 [get_ports {clk}]
create_generated_clock -name mid_clk -source [get_ports {clk}] -multiply_by 16 -divide_by 25 [get_pins {clocks/pll1/CLKOUT0}]
create_generated_clock -name audio_clk -source [get_pins {clocks/pll1/CLKOUT0}] -multiply_by 48 -divide_by 25 [get_pins {clocks/pll2/CLKOUT0}]
# UART TX route budget; RX is asynchronous and synchronized in uart_rx.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {bt_tx}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {bt_tx}] 0.000
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


# Human-visible LEDs: deliberate 100ns output-route budget, no audio timing exception.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4]}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4]}] 0.000
# U7 SPI is registered ref-clock data with a 500ns half-period at default1MHz.
# 100ns is a bounded output-route budget; no internal audio/memory path exception.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {flash_cs_n flash_sck flash_mosi flash_wp_n flash_hold_n}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {flash_cs_n flash_sck flash_mosi flash_wp_n flash_hold_n}] 0.000

# Independent 35MHz trial LCD PLL; actual production PCLK_INVERT=1.
create_generated_clock -name pixel_clk -source [get_ports {clk}] -multiply_by 7 -divide_by 10 [get_pins {lcd_on.display_driver/pixel_pll/CLKOUT0}]
# Source-synchronous LCD via the global-clock IO DDR cell, inverted phase.
# The 6ns source reference is checked against independent ODDR D1 timing:
# Slow insertion >=6ns, Fast insertion <=6ns. Do not accept a build otherwise.
# Original8.286ns setup reservation remains. Hold reserves1ns plus at most5ns
# for physical CLK->Q0->OBUF->pin, independently checked in same-build SDF.
create_generated_clock -name lcd_pclk -source [get_pins {lcd_on.display_driver/pixel_pll/CLKOUT0}] -divide_by 1 -invert [get_pins {lcd_on.display_driver/pixel_clock_forward/Q0}]
set_clock_latency -source -early 6.000 [get_clocks {lcd_pclk}]
set_clock_latency -source -late 6.000 [get_clocks {lcd_pclk}]
set_output_delay -clock lcd_pclk 8.286 -max [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}]
set_output_delay -clock lcd_pclk -6.000 -min [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}]
# Preserve the20ns forwarding route bound; no ordinary data path relaxation.
set_max_delay -from [get_clocks {pixel_clk}] -to [get_ports {lcd_clk}] 20.000
set_min_delay -from [get_clocks {pixel_clk}] -to [get_ports {lcd_clk}] 0.000
set_max_delay -from [get_pins {lcd_on.display_driver/pixel_clock_forward/CLK}] -to [get_ports {lcd_clk}] 20.000
set_min_delay -from [get_pins {lcd_on.display_driver/pixel_clock_forward/CLK}] -to [get_ports {lcd_clk}] 0.000

# Touch controller is entirely in ref_clk; SCL is registered open-drain data,
# never an internal clock. Inputs pass through two registers inside the master.
# 100ns is an implementation route budget versus 5us nominal half-period,
# not a substitute for measuring pull-up rise time or panel IO voltage.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {touch_scl touch_sda touch_int touch_rst_n}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {touch_scl touch_sda touch_int touch_rst_n}] 0.000

# Separate domain reports: global worst paths otherwise hide audio/ref logic
# behind the LCD output budgets. Report commands do not change constraints.
report_timing -setup -from_clock [get_clocks {ref_clk}] -to_clock [get_clocks {ref_clk}] -max_paths 25 -max_common_paths 1
report_timing -setup -from_clock [get_clocks {audio_clk}] -to_clock [get_clocks {audio_clk}] -max_paths 25 -max_common_paths 1
report_timing -setup -from_clock [get_clocks {pixel_clk}] -to_clock [get_clocks {pixel_clk}] -max_paths 25 -max_common_paths 1

# Include external and inter-domain paths as well as the three per-domain reports.
report_timing -setup -max_paths 50 -max_common_paths 1

# Asynchronous assertion boundary of five explicit two-stage pixel reset synchronizers.
# Only these PRESET pins are excepted; D/Q, intermediate stages and data paths remain timed.
set_false_path -to [get_pins {lcd_on.display_driver/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/pixel_reset_sync/pipe_1_s0/PRESET lcd_on.display_driver/status_bridge/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/status_bridge/pixel_reset_sync/pipe_1_s0/PRESET lcd_on.display_driver/more_bridge/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/more_bridge/pixel_reset_sync/pipe_1_s0/PRESET lcd_on.display_driver/performance_bridge/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/performance_bridge/pixel_reset_sync/pipe_1_s0/PRESET lcd_on.display_driver/analysis_bridge/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/analysis_bridge/pixel_reset_sync/pipe_1_s0/PRESET}]
report_timing -setup -to [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}] -max_paths 25 -max_common_paths 1

report_timing -setup -to [get_ports {lcd_clk}] -max_paths 5 -max_common_paths 1

# Ultrasound Trig is registered ref-clock data, not an internal clock.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {ultrasonic_trig}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {ultrasonic_trig}] 0.000
# Three independent open-drain keypad buses; inputs synchronized by each master.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {keypad_sda[*] keypad_scl[*]}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {keypad_sda[*] keypad_scl[*]}] 0.000

# Independent, physically checked forward-clock reference.
report_timing -setup -to [get_pins {lcd_on.display_driver/pixel_clock_forward/D1}] -max_paths 2
report_timing -hold -to [get_pins {lcd_on.display_driver/pixel_clock_forward/D1}] -max_paths 2
report_timing -setup -from [get_pins {lcd_on.display_driver/pixel_clock_forward/CLK}] -to [get_ports {lcd_clk}] -max_paths 2
report_timing -hold -from [get_pins {lcd_on.display_driver/pixel_clock_forward/CLK}] -to [get_ports {lcd_clk}] -max_paths 2
