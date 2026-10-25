`timescale 1ns/1ps
`include "check.svh"
module tb_timbre_control;
 parameter integer N=4,L=100;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] buttons=15;integer checks=0;
 wire [2:0] timbre;wire en,zh,menu;wire [1:0] theme;
 timbre_control #(.DEBOUNCE_CYCLES(N),.LONG_PRESS_CYCLES(L)) dut(
 .clk(clk),.rst(rst),.buttons_n(buttons),.selected(timbre),.effects_enabled(en),
 .theme_id(theme),.language_zh(zh),.menu_mode(menu),.ui_action_valid(1'b0),.ui_action(6'd63),.cfg_ready(1'b1));
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin
 #12 rst=0;cycles(N+8);
 for(integer b=0;b<3;b=b+1)begin
  buttons=15^(1<<b);cycles(L+N+10);buttons=15;cycles(N+8);
  `CHECK(timbre==0 && theme==0 && !menu && !en && !zh,"reserved buttons never alter state")
 end
 if(N>1)begin buttons=7;cycles(N-1);buttons=15;cycles(N+8);`CHECK(theme==0,"S3 bounce rejected") end
 buttons=7;cycles(L+N+10);`CHECK(theme==3,"debounced long press enters hidden theme")
 cycles(L*2);`CHECK(theme==3,"one action per long hold")
 buttons=15;cycles(N+8);`CHECK(theme==3 && !en,"long release has no effect toggle")
 buttons=7;cycles(L+N+10);buttons=15;cycles(N+8);`CHECK(theme==0,"second long S3 returns normal theme")
 rst=1;#1;`CHECK(theme==0 && !en && !zh,"reset clears hidden and language state")
 $display("PASS tb_timbre_control checks=%0d",checks);$finish;
 end
endmodule
