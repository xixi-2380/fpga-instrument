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

# Open-drain column enable paths; row inputs are asynchronous and two-flop synchronized.
set_max_delay -from [get_clocks {audio_clk}] -to [get_ports {key_col[0] key_col[1] key_col[2] key_col[3]}] 30.000
set_min_delay -from [get_clocks {audio_clk}] -to [get_ports {key_col[0] key_col[1] key_col[2] key_col[3]}] 0.000

# Human-visible LEDs: deliberate 100ns output-route budget, no audio timing exception.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4]}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4]}] 0.000
# U7 SPI is registered ref-clock data with a 500ns half-period at default1MHz.
# 100ns is a bounded output-route budget; no internal audio/memory path exception.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {flash_cs_n flash_sck flash_mosi flash_wp_n flash_hold_n}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {flash_cs_n flash_sck flash_mosi flash_wp_n flash_hold_n}] 0.000

# Independent 35MHz trial LCD PLL; actual production PCLK_INVERT=1.
create_generated_clock -name pixel_clk -source [get_ports {clk}] -multiply_by 7 -divide_by 10 [get_pins {lcd_on.display_driver/pixel_pll/CLKOUT0}]
# Source-synchronous LCD interface: PCLK is inverted only at the output port,
# and does not clock internal logic. Include its physical clock forwarding path.
create_generated_clock -name lcd_pclk -source [get_pins {lcd_on.display_driver/pixel_pll/CLKOUT0}] -divide_by 1 -invert [get_ports {lcd_clk}]
# Gowin treats the external sampling clock as ideal unless its source latency
# is declared. Slow-corner PLL insertion5.383 + pad2.528 is already7.911ns,
# before inverter/wire delay. Use7.5ns as a conservative early bound; use20ns
# as late bound and explicitly constrain/report the forwarding path below.
set_clock_latency -source -early 7.500 [get_clocks {lcd_pclk}]
set_clock_latency -source -late 20.000 [get_clocks {lcd_pclk}]
set_max_delay -from [get_clocks {pixel_clk}] -to [get_ports {lcd_clk}] 20.000
# Preserve the intended <=6ns DATA-to-forwarded-clock skew budget:
# half-period14.286 - output reservation8.286 = 6ns. Unlike absolute max-delay,
# common clock insertion latency is not incorrectly charged to DATA alone.
# These are engineering budgets, NOT a verified panel/board timing specification.
# Receiver hold reservation remains0ns. No internal path is exempted.
set_output_delay -clock lcd_pclk 8.286 -max [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}]
set_output_delay -clock lcd_pclk 0.000 -min [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}]

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

# These six PRESET pins are the asynchronous assertion boundary of three
# reset_sync instances. Deassertion propagates through two pixel-clock FFs.
# D, Q, the stage-to-stage path, and every downstream register remain timed.
set_false_path -to [get_pins {lcd_on.display_driver/status_bridge/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/status_bridge/pixel_reset_sync/pipe_1_s0/PRESET lcd_on.display_driver/more_bridge/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/more_bridge/pixel_reset_sync/pipe_1_s0/PRESET lcd_on.display_driver/pixel_reset_sync/pipe_0_s0/PRESET lcd_on.display_driver/pixel_reset_sync/pipe_1_s0/PRESET}]
report_timing -setup -to [get_ports {lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}] -max_paths 25 -max_common_paths 1

report_timing -setup -to [get_ports {lcd_clk}] -max_paths 5 -max_common_paths 1

# Ultrasound Trig is registered ref-clock data, not an internal clock.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {ultrasonic_trig}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {ultrasonic_trig}] 0.000
