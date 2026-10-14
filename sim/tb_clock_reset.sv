`timescale 1ns/1ps
`include "check.svh"
module tb_clock_reset;
 reg refclk=0,aclk=0,ext=1,l1=0,l2=0;
 always #10 refclk=~refclk;always #8.138 aclk=~aclk;
 wire p1,p2,ar;integer checks=0;
 clock_reset #(.LOCK_N(8)) dut(refclk,ext,l1,l2,aclk,p1,p2,ar);
 initial begin
  #35 ext=0;wait(!p1);`CHECK(p2 && ar,"PLL2 held before PLL1 lock")
  #3 l1=1;wait(!p2);`CHECK(ar,"audio held before PLL2 lock")
  #3 l2=1;wait(!ar);`CHECK(!p1 && !p2,"staged release")
  #3 l1=0;#1;`CHECK(ar && p2,"loss of first PLL asserts reset")
  #5 l1=1;wait(!p2);wait(!ar);
  #3 l2=0;#1;`CHECK(ar,"loss of second PLL asserts reset")
  #9 ext=1;#1;`CHECK(p1 && p2 && ar,"external reset")
  $display("PASS tb_clock_reset checks=%0d",checks);$finish;
 end
 initial begin #20000;$fatal(1,"timeout");end
endmodule
