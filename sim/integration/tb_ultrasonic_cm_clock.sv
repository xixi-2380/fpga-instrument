`timescale 1ns/1ps
module tb_ultrasonic_cm_clock;
 reg clk=0,rst=1,en=1,echo=0;always #10 clk=~clk;
 wire trig,report,valid;wire[12:0]cm;
 ultrasonic_range #(.CLOCK_HZ(50000000),.PERIOD_US(24000)) dut(clk,rst,en,echo,trig,report,valid,cm);
 integer checks=0;
 task pulse(input integer width_us,phase_ns,expected);begin
  @(posedge trig);@(negedge trig);#(17000+phase_ns);echo=1;#(width_us*1000);echo=0;
  @(posedge report);#1;
  if(cm!==expected || valid!==(expected>=2 && expected<=400))$fatal(1,"50MHz echo pulse width%0dus phase%0dns got%0d expected%0d",width_us,phase_ns,cm,expected);
  checks++;
 end endtask
 initial begin
  #105;rst=0;
  pulse(116,0,2);pulse(580,10,10);pulse(5800,377,100);pulse(23200,991,400);
  // Phase within the 1us CE must not turn a 58us/cm whole-cm pulse into mm.
  pulse(1305,533,23);pulse(608,23,10);pulse(609,773,11);
  pulse(58,93,1);pulse(23258,617,401);
  en=0;#100;if(trig||valid)$fatal(1,"Production clock disable failed");checks++;
  $display("PASS tb_ultrasonic_cm_clock checks=%0d clock_hz=50000000",checks);$finish;
 end
 initial begin #300000000;$fatal(1,"50MHz real echo timeout");end
endmodule
