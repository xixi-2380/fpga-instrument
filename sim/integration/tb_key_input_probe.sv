`timescale 1ns/1ps
module tb_key_input_probe;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [35:0] keys=0;reg [2:0] valid=0;
 wire p1,p2,p50000;
 key_input_probe #(.PULSE_CYCLES(1)) a(clk,rst,keys,valid,p1);
 key_input_probe #(.PULSE_CYCLES(2)) b(clk,rst,keys,valid,p2);
 key_input_probe c(clk,rst,keys,valid,p50000);
 integer ticks=0,last_press=-100000,checks=0,events=0;
 reg [35:0] seen=0,q;
 always @(posedge clk)begin
  ticks=ticks+1;
  if(rst)begin seen=0;last_press=-100000;end
  else begin
   for(integer j=0;j<36;j++)q[j]=valid[j/12] && keys[j];
   if((q&~seen)!=0)begin last_press=ticks;events++;end
   seen=q;
  end
  #1;
  checks++;
  if(p1!==(!rst && ticks-last_press<1) || p2!==(!rst && ticks-last_press<2) ||
     p50000!==(!rst && ticks-last_press<50000))$fatal(1,"pulse width/reset mismatch tick %0d",ticks);
 end
 task step(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
  step(2);rst=0;keys=36'hfffffffff;step(4);
  if(events!=0)$fatal(1,"offline keys triggered");
  valid=7;step(50002);if(p50000)$fatal(1,"held key retriggered");
  keys=0;step(3);
  for(integer j=0;j<36;j++)begin keys[j]=1;step(3);keys[j]=0;step(3);end
  step(50002);
  keys[0]=1;step(49999);keys[35]=1;step(2);
  if(!p50000)$fatal(1,"retrigger failed");
  valid[2]=0;step(3);valid[2]=1;step(3);
  #3 rst=1;#1;if(p1||p2||p50000)$fatal(1,"async reset failed");
  step(2);keys=0;rst=0;step(50002);
  $display("PASS tb_key_input_probe checks=%0d events=%0d",checks,events);$finish;
 end
endmodule
