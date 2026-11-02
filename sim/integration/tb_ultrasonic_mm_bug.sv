`timescale 1ns/1ps
// Kept old modules expose the real tenfold mistake with a 10cm/580us echo.
module tb_ultrasonic_mm_bug;
 reg clk=0,rst=1,en=1,echo=0;always #500 clk=~clk;
 wire trig,report,valid;wire[12:0]old_distance;wire[17:0]ratio;wire[2:0]status;wire[11:0]bcd;wire[7:0]applied;
 baseline_ultrasonic_range #(.CLOCK_HZ(1000000)) sensor(clk,rst,en,echo,trig,report,valid,old_distance);
 baseline_ultrasonic_pitch #(.CLOCK_HZ(1000000)) pitch(clk,rst,1'b1,en,3'd1,7'd5,7'd40,8'd1,report,valid,old_distance,ratio,status,bcd,applied);
 initial begin
  repeat(3)@(negedge clk);rst=0;@(posedge trig);@(negedge trig);
  repeat(17)@(negedge clk);echo=1;repeat(580)@(negedge clk);echo=0;
  @(posedge report);repeat(32)@(negedge clk);
  if(old_distance!==100 || bcd!==12'h100)$fatal(1,"Old tenfold unit bug fixture was not reproduced");
  $display("PASS tb_ultrasonic_mm_bug checks=2 physical_cm=10 legacy_distance_mm=%0d legacy_bcd=%h renderer_suffix=CM incorrect_screen=100_CM",old_distance,bcd);$finish;
 end
 initial begin #10000000;$fatal(1,"Old bug reproduction timeout");end
endmodule
