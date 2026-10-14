create_clock -name ref_clk -period 20.000 [get_ports {clk}]
create_generated_clock -name mid_clk -source [get_ports {clk}] -multiply_by 16 -divide_by 25 [get_pins {engine/clocks/pll1/CLKOUT0}]
create_generated_clock -name audio_clk -source [get_pins {engine/clocks/pll1/CLKOUT0}] -multiply_by 48 -divide_by 25 [get_pins {engine/clocks/pll2/CLKOUT0}]
# Conservative implementation budget: output arrival before the NEXT audio
# clock edge with 4 ns reserved. This is much tighter than 325.52 ns BCK half-bit.
# It is NOT a guessed PT8211 setup/hold specification or an electrical signoff.
set_output_delay -clock audio_clk -max 4.000 [get_ports {HP_BCK HP_WS HP_DIN PA_EN}]
set_output_delay -clock audio_clk -min 0.000 [get_ports {HP_BCK HP_WS HP_DIN PA_EN}]
# rst is an asynchronous button, not a synchronous data input. No fake
# input arrival time is imposed; its reset synchronizer is checked by TB.
