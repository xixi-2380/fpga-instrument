`timescale 1ns/1ps
module tb_pcb_debug_ui;
 reg clk=0,rst=1,menu=0,ack=0,av=0;always #5 clk=~clk;
 reg visible=0;reg [6:0] action=63;reg [1023:0] hw=0;reg [383:0] enc=0;reg [319:0] audio=0;
 wire mute,page;wire [159:0] control;wire [2:0] clear;wire [2591:0] display;
 integer checks=0;reg [2559:0] frozen_lines;
 pcb_debug_ui dut(clk,rst,1'b1,menu,ack,av,action,1'b1,hw,enc,12'd0,audio,mute,page,control,clear,display,visible);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 // Allow shared BCD conversion (25*19 clocks) and complete-frame publication.
 task act(input [5:0] a);begin @(negedge clk);action=a;av=1;@(negedge clk);av=0;repeat(1400)@(negedge clk);end endtask
 initial begin
  hw[771:640]={{16{8'd4}},4'd2};hw[903:772]={{16{8'd4}},4'd2};hw[908:906]=7;hw[911:909]=7;hw[608:592]='1;hw[609]=1;
  repeat(3)@(negedge clk);rst=0;menu=1;act(42);
  check(mute && !page,"debug waits for verified final audio mute before showing");ack=1;repeat(20)@(negedge clk);
  check(page && display[2560],"muted page opens");
  @(negedge clk);audio[43:42]=2'b11;@(negedge clk);audio[42]=0;audio[44]=1;
  @(negedge clk);audio[44]=0;repeat(20)@(negedge clk);
  check(dut.cfg_accept_count==1 && dut.cfg_apply_count==1,"single-clock effect handshake pulses survive the slow display refresh");
  act(48);check(display[6*320+319-:6*8]=="CFG OK","accepted/applied event counts are visible");
  act(50);act(50);hw[905:904]=2;audio[35:24]=12'h805;audio[291:280]=12'h800;
  act(47);repeat(1400)@(negedge clk);
  check(dut.selected_route==12'h805 && dut.selected_armed==12'h800,"third-board highest keys are represented in routed and armed stages");
  act(49);act(49);hw[905:904]=0;audio=0;repeat(1400)@(negedge clk);
act(45);check(dut.tab==1,"sensitivity tab");
  hw[609]=0;repeat(1400)@(negedge clk);
  check(display[2*320+319-:6*8]=="SAVED:","power-on fallback is never displayed as a successfully applied configuration");
  hw[609]=1;hw[593]=0;act(62);act(62);act(62);repeat(1400)@(negedge clk);
  check(display[1*320+:320]=="UNVERIFIED READ  : FFFFFFFF             ","partial grouped readback cannot display unverified channels as actual values");
  hw[593]=1;repeat(1400)@(negedge clk);
  check(display[1*320+:320]=="READBACK CH GRP  : 04040404             ","all four verified channels enable the grouped readback");
  act(62);
  repeat(20)act(54);check(dut.draft[0][3:0]==15,"GSR upper bound is enforced");
  repeat(20)act(53);check(dut.draft[0][3:0]==0,"GSR lower bound is enforced");
  act(58);act(55);repeat(8)act(53);check(dut.draft[0][11:4]==1,"KOR cannot reach zero");
  repeat(260)act(54);check(dut.draft[0][11:4]==255,"KOR saturates at byte maximum");act(58);act(55);

  act(54);check(dut.draft[0][3:0]==3 && hw[643:640]==2,"editing does not write hardware");
  act(55);act(54);act(56);check(dut.draft[0][11:4]==5 && dut.draft[0][131:124]==5,"per-key edit and all-KOR copy");
  act(57);check(dut.pending && control[11:4]==1 && control[15:12]==3,"apply holds an atomic parameter request");
  act(54);check(dut.draft[0][11:4]==5,"pending apply cannot mutate its draft");
  hw[919:912]=1;hw[927:920]=8'h23;repeat(24)@(negedge clk);
  check(!dut.pending && dut.last_result[0]==8'h23,"configuration failure is visible without fabricated success");
  act(58);check(dut.draft[0]=={{16{8'd4}},4'd2},"defaults alter draft only");
  act(60);repeat(24)@(negedge clk);frozen_lines=display[2559:0];hw[207:176]=32'h12345678;
  repeat(300)@(negedge clk);check(display[2559:0]==frozen_lines,"freeze holds displayed telemetry");
  act(60);repeat(1400)@(negedge clk);check(dut.captured[207:176]==32'h12345678,"unfreeze resumes acquisition display");
  act(61);check(control[151:144]==1,"clear sends a separate statistics request");
  act(50);hw[905:904]=1;repeat(1400)@(negedge clk);check(dut.board==1 && dut.draft[1][3:0]==2,"board sensitivity is independent");
  act(48);check(dut.tab==4,"encoder page");visible=1;act(43);
  check(!page && mute,"return stays muted while the previous LCD frame is still visible");
  visible=0;repeat(4)@(negedge clk);check(!mute,"mute releases after the actual renderer leaves debug");
  act(42);menu=0;repeat(5)@(negedge clk);check(!page && !mute,"original S0 menu exit closes debug without a remap");
  $display("PASS tb_pcb_debug_ui checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"PCB UI timeout");end
endmodule
