create_clock -name ref_clk -period 20.000 [get_ports {clk}]
create_generated_clock -name mid_clk -source [get_ports {clk}] -multiply_by 16 -divide_by 25 [get_pins {engine/clocks/pll1/CLKOUT0}]
create_generated_clock -name audio_clk -source [get_pins {engine/clocks/pll1/CLKOUT0}] -multiply_by 48 -divide_by 25 [get_pins {engine/clocks/pll2/CLKOUT0}]
# BCK is the forwarded capture clock; data/WS launch on its falling edge.
create_generated_clock -name dac_bck -source [get_pins {engine/clocks/pll2/CLKOUT0}] -divide_by 40 [get_ports {HP_BCK}]
# Engineering margin targets, NOT numeric limits quoted from PT8211 datasheet.
set_output_delay -clock dac_bck -max 50.000 [get_ports {HP_WS HP_DIN}]
set_output_delay -clock dac_bck -min -20.000 [get_ports {HP_WS HP_DIN}]
# The CE schedule gives exactly 20 source periods from a data change to BCK
# rising capture. Source-clock multicycle uses 19 additional AUDIO periods,
# not 19 BCK periods. The paired hold exception removes the setup-only shift.
# This relationship is checked at pins by tb_bringup_digital/tb_pt8211_tx.
set_multicycle_path 20 -setup -start -from [get_clocks {audio_clk}] -to [get_ports {HP_WS HP_DIN}]
set_multicycle_path 19 -hold -start -from [get_clocks {audio_clk}] -to [get_ports {HP_WS HP_DIN}]
# rst is an asynchronous button, not a synchronous data input. No fake
# input arrival time is imposed; its reset synchronizer is checked by TB.
