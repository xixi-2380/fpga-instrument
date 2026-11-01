`timescale 1ns/1ps
module tb_pnr_pcb_equivalence;
 reg clk=0,rst=1,ms_ce=0,menu=1,ack=1,av=0,hardware_valid=1,visible=0;
 always #5 clk=~clk;
 reg [6:0] action=63;reg [1023:0] hw=0;reg [383:0] enc=0;reg [11:0] events=0;reg [319:0] audio=0;
 wire mute_a,page_a,mute_b,page_b;wire [159:0] ctrl_a,ctrl_b;
 wire [2:0] clear_a,clear_b;wire [2591:0] display_a,display_b;
 reg [31:0] random_state=32'h2468ace1;reg [7:0] reset_rows=0;reg [2559:0] previous=0;
 integer checks=0,publications=0;
 pcb_debug_ui a(clk,rst,ms_ce,menu,ack,av,action,hardware_valid,hw,enc,events,audio,mute_a,page_a,ctrl_a,clear_a,display_a,visible);
 reference_pcb_debug_ui_c6352fa b(clk,rst,ms_ce,menu,ack,av,action,hardware_valid,hw,enc,events,audio,mute_b,page_b,ctrl_b,clear_b,display_b,visible);
 always @(posedge clk)begin
  #1;checks=checks+1;
  if({mute_a,page_a,ctrl_a,clear_a,display_a} !== {mute_b,page_b,ctrl_b,clear_b,display_b})
   $fatal(1,"PCB external output mismatch check=%0d",checks);
  if(display_a[2559:0]!==previous && display_a[2559:0]!==0)publications=publications+1;
  previous=display_a[2559:0];
 end
 initial begin
  hw[771:640]={{16{8'd4}},4'd2};hw[903:772]={{16{8'd4}},4'd2};hw[609:592]='1;
  repeat(3)@(negedge clk);rst=0;
  for(integer i=0;i<180000;i=i+1)begin
   @(negedge clk);
   random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
   rst=0;ms_ce=i%4==0;av=0;events=0;
   if(i%1800==0)begin action=42;av=1;menu=1;end
   else if(i%1800==1)av=0;
   else if(i%1800==1000)begin action=44+((i/1800)%5);av=1;end
   else if(i%1800==1300)begin action=49+((i/1800)%14);av=1;end
   else if(i%1800==1500)begin action=43;av=1;end
   if(i%17==0)begin
    for(integer w=0;w<32;w=w+1)hw[w*32+:32]=random_state^(w*32'h1234567);
    hw[905:904]=a.board;hw[919:912]=a.sequence_id;hw[927:920]=0;
    for(integer w=0;w<12;w=w+1)enc[w*32+:32]=random_state^(w*17);
    audio[319:0]={10{random_state}};
   end
   hardware_valid=(i%2000<1600);ack=(i%3000<2900);visible=page_a;
   if(i%31==0)events=random_state[11:0];
   // Reset each private row at least once, including partial formatting.
   if(a.building && !reset_rows[a.row] && a.format_phase==2)begin
    reset_rows[a.row]=1;rst=1;av=0;
   end
  end
  rst=0;av=0;repeat(10)@(negedge clk);
  if(reset_rows!=8'hff || publications<20)$fatal(1,"coverage rows=%h publications=%0d",reset_rows,publications);
  $display("PASS tb_pnr_pcb_equivalence checks=%0d publications=%0d reset_rows=%h",checks,publications,reset_rows);$finish;
 end
endmodule
