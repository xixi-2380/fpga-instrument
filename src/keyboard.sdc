create_clock -name ref_clk -period 20.000 [get_ports {clk}]
create_generated_clock -name mid_clk -source [get_ports {clk}] -multiply_by 16 -divide_by 25 [get_pins {clocks/pll1/CLKOUT0}]
create_generated_clock -name audio_clk -source [get_pins {clocks/pll1/CLKOUT0}] -multiply_by 48 -divide_by 25 [get_pins {clocks/pll2/CLKOUT0}]
# Bound every registered output path to 0..30 ns, including implementation
# clock insertion. No generated clock is placed on the BCK DATA net: Gowin
# otherwise propagates that clock into BCK's counter/CE fanout.
# BCK and WS/DIN change on the SAME source edge; the receiving edge is 20
# audio cycles later (325.52 ns). Thus this bound leaves at least 295.52 ns
# nominal setup/hold spacing before board skew, to be measured on hardware.
# 30 ns is a deliberate route budget, NOT a guessed PT8211 datasheet limit.
# No audio paths are false-pathed or granted an unproven multicycle exception.
set_max_delay -from [get_clocks {audio_clk}] -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN DBG_BCK DBG_WS DBG_DIN DBG_PA_EN}] 30.000
set_min_delay -from [get_clocks {audio_clk}] -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN DBG_BCK DBG_WS DBG_DIN DBG_PA_EN}] 0.000
# rst is an asynchronous button, not a synchronous data input. No fake
# input arrival time is imposed; its reset synchronizer is checked by TB.

# Open-drain column enable paths; row inputs are asynchronous and two-flop synchronized.
set_max_delay -from [get_clocks {audio_clk}] -to [get_ports {key_col[0] key_col[1] key_col[2] key_col[3]}] 30.000
set_min_delay -from [get_clocks {audio_clk}] -to [get_ports {key_col[0] key_col[1] key_col[2] key_col[3]}] 0.000

# Human-visible LEDs: deliberate 100ns output-route budget, no audio timing exception.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4] led_n[5]}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {led_n[0] led_n[1] led_n[2] led_n[3] led_n[4] led_n[5]}] 0.000

# Independent 35 MHz trial LCD PLL, from Sipeed's Pro 800x480 example.
# This does not alter either existing audio PLL or relax audio paths.
# The renderer launches RGB/DE on pixel_clk rising edges. The default
# forwarded PCLK is inverted, so its rising sampling edge is half a cycle later.
# 6ns is an internal routing budget (leaves 8.286ns nominal at 35MHz), NOT
# panel setup/hold specification. External setup/hold and board skew await measurement.
# No blanket asynchronous clock groups or payload false paths are added.
# Flat Gowin SDC command syntax, not a general Tcl script.
# Synthesized generate instance name is lcd_on.display_driver (dot preserved).
# This section is for LCD_ENABLE=1; remove these three commands if disabling LCD.
create_generated_clock -name pixel_clk -source [get_ports {clk}] -multiply_by 7 -divide_by 10 [get_pins {lcd_on.display_driver/pixel_pll/CLKOUT0}]
set_max_delay -from [get_clocks {pixel_clk}] -to [get_ports {lcd_clk lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}] 6.000
set_min_delay -from [get_clocks {pixel_clk}] -to [get_ports {lcd_clk lcd_hs lcd_vs lcd_en lcd_r[*] lcd_g[*] lcd_b[*]}] 0.000

# Touch controller is entirely in ref_clk; SCL is registered open-drain data,
# never an internal clock. Inputs pass through two registers inside the master.
# 100ns is an implementation route budget versus 5us nominal half-period,
# not a substitute for measuring pull-up rise time or panel IO voltage.
set_max_delay -from [get_clocks {ref_clk}] -to [get_ports {touch_scl touch_sda touch_int touch_rst_n}] 100.000
set_min_delay -from [get_clocks {ref_clk}] -to [get_ports {touch_scl touch_sda touch_int touch_rst_n}] 0.000
