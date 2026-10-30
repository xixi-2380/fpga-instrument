`timescale 1ns/1ps
module tb_pcb_readable;
 reg clk=0,rst=1,av=0;always #5 clk=~clk;
 reg [6:0] action=63;reg [1023:0] hw=0;reg [319:0] audio=0;
 wire [2591:0] display;integer checks=0;
 pcb_debug_ui dut(.clk(clk),.rst(rst),.ms_ce(1'b1),.menu_mode(1'b1),.mute_ack(1'b1),.action_valid(av),.action(action),
 .hardware_valid(1'b1),.hardware(hw),.encoder_diag(384'd0),.encoder_events(12'd0),.audio_status(audio),.display(display),.display_visible(1'b1));
 task act(input [5:0] code);begin @(negedge clk);action=code;av=1;@(negedge clk);av=0;repeat(160)@(negedge clk);end endtask
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 initial begin
  hw[771:640]={{16{8'd4}},4'd2};hw[903:772]={{16{8'd4}},4'd2};hw[609]=1;hw[608:592]='1;
  hw[139]=1;hw[140]=1;hw[142]=1;audio[93:85]=2000%512;audio[294:293]=2000/512;
  audio[77:74]=4;audio[292]=1;audio[59:53]=25;audio[73:67]=50;
  repeat(3)@(negedge clk);rst=0;act(42);
  check(display[1*320+319-:24*8]=="LINK ONLINE   DATA READY","overview decodes communication and freshness into words");
  act(45);check(display[1*320+319-:10*8]=="EDIT  GSR ","sensitivity default view names editable parameters");
  check(display[5*320+319-:5*8]=="GSR +","sensitivity direction is shown directly");
  act(48);check(display[5*320+319-:30*8]=="SUSTAIN  2000 ms  LEVEL    25%","2s is displayed in decimal without the old9-bit wrap");
  act(50);hw[905:904]=1;audio[295]=1;audio[84:78]=64;repeat(240)@(negedge clk);
  check(display[5*320+319-:34*8]=="MASTER VOLUME    64% / CLICK: ROOM","knob2 reports the real master-volume editing mode");
  audio[295]=0;act(50);hw[905:904]=2;repeat(240)@(negedge clk);
  check(display[5*320+319-:31*8]=="TREM DEPTH    50% RATE    20 Hz","20Hz and strength are human-readable");
  act(62);check(display[1*320+319-:15*8]=="EC11 PCB EVENTS","advanced history remains accessible");
  $display("PASS tb_pcb_readable checks=%0d",checks);$finish;
 end
endmodule
