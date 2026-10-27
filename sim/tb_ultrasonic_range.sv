`timescale 1ns/1ps
`include "check.svh"
module tb_ultrasonic_range;
 reg clk=0,rst=1,enabled=0,echo=0;always #500 clk=~clk;
 wire trig,report,valid;wire [12:0] mm;
 integer checks=0,cycles_count=0,last_trigger=-60000,started=0,pulse_start;
 ultrasonic_range #(.CLOCK_HZ(1000000)) dut(clk,rst,enabled,echo,trig,report,valid,mm);
 always @(posedge clk)cycles_count=cycles_count+1;
 always @(posedge trig)begin
  `CHECK(cycles_count-last_trigger>=60000,"triggers separated by at least 60ms")
  last_trigger=cycles_count;pulse_start=cycles_count;started=started+1;
 end
 always @(negedge trig)if(!rst && enabled && started>0)
  `CHECK(cycles_count-pulse_start==12,"12us trigger pulse")
 task measure(input integer width_us,expected_mm);begin
  @(posedge trig);@(negedge trig);#17000;echo=1;
  #(width_us*1000);echo=0;
  @(posedge report);#1;
  `CHECK(valid && mm>=expected_mm-1 && mm<=expected_mm+1,"echo width converts to rounded millimetres")
 end endtask
 initial begin
  #2200;rst=0;repeat(80)@(negedge clk);`CHECK(!trig && started==0,"disabled sensor never triggers")
  enabled=1;
  measure(290,50);measure(580,100);measure(1160,200);measure(2320,400);measure(5800,1000);
  @(posedge trig);@(negedge trig);@(posedge report);#1;`CHECK(!valid,"missing echo times out")
  @(posedge trig);@(negedge trig);#17000;echo=1;
  @(posedge report);#1;`CHECK(!valid,"stuck-high echo times out")
  repeat(61000)@(negedge clk);`CHECK(!trig,"pre-existing high echo does not start another trigger")
  enabled=0;echo=0;repeat(10)@(negedge clk);`CHECK(!trig && !valid,"disable cancels acquisition")
  // Reset inter-trigger accounting because a new enabled session may start immediately.
  last_trigger=-60000;enabled=1;@(posedge trig);#2500;rst=1;#1;
  `CHECK(!trig && !valid,"asynchronous reset cancels trigger")
  $display("PASS tb_ultrasonic_range checks=%0d triggers=%0d",checks,started);$finish;
 end
 initial begin #1000000000;$fatal(1,"ultrasonic range timeout");end
endmodule
