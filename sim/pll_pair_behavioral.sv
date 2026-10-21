`timescale 1ns/1ps
// Test-only clock/lock substitute. Does not validate vendor PLL behavior or STA.
// Compile instead of src/pll_pair.sv; never add to the hardware project.
module pll_pair(input wire ref_clk,rst,pll2_rst,
 output reg mid_clk,audio_clk,output wire lock1,lock2);
 initial begin mid_clk=0;audio_clk=0;end
 always #4 mid_clk=~mid_clk;
 always #8.138020833 audio_clk=~audio_clk;
 assign lock1=!rst;
 assign lock2=!pll2_rst && lock1;
endmodule
