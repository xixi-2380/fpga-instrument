`timescale 1ns/1ps
module tb_bt_event_cdc;
 reg sclk=0,aclk=0,rst=1,sv=0,ar=0;
 always #10 sclk=~sclk;always #7 aclk=~aclk;
 reg [22:0] data=0;wire sr,av;wire [22:0] result;
 integer checks=0,accepted=0;
 bt_event_cdc dut(sclk,aclk,rst,sv,sr,data,av,ar,result);
 task check(input bit b,input string msg);begin checks++;if(!b)$fatal(1,"%s",msg);end endtask
 always @(posedge aclk)if(av && ar)begin check(result==data,"whole event crosses atomically");accepted++;end
 initial begin
  #30 rst=0;repeat(5)@(negedge sclk);
  for(integer n=0;n<64;n++)begin
   data={n[6:0],n[6:0],n[6:0],2'b10};sv=1;ar=0;
   wait(av);repeat(5)@(negedge aclk);
   check(!sr && result==data,"source waits for actual audio acceptance under stall");
   ar=1;wait(sr);@(posedge sclk);#1;@(negedge sclk);sv=0;ar=0;repeat(2)@(negedge sclk);
  end
  check(accepted==64,"exactly once delivery");
  sv=1;data=23'h712345;ar=0;wait(av);#3;rst=1;#1;
  repeat(4)@(negedge sclk);check(!sr && !av,"common reset drops pending transfer");
  sv=0;rst=0;repeat(5)@(negedge sclk);ar=1;repeat(5)@(negedge aclk);
  check(accepted==64,"reset pending event never reappears");
  $display("PASS tb_bt_event_cdc checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"CDC timeout");end
endmodule
