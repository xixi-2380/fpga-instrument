`timescale 1ns/1ps
// Real trigger/echo pins, 58us/cm. Timing is accelerated only by using the
// supported 1MHz CLOCK_HZ; all physical pulse durations are still real us.
module tb_ultrasonic_cm_echo;
 reg clk=0,rst=1,en=1,echo=0,cfg=1,report_enable=1;
 always #500 clk=~clk;
 wire trig,report,valid;wire[12:0]cm;wire[17:0]ratio;
 wire[2:0]status;wire[11:0]bcd;wire[7:0]applied;
 reg[2:0]band=1;reg[6:0]minimum=5,maximum=40;reg[7:0]version=1;
 ultrasonic_range #(.CLOCK_HZ(1000000)) range_sensor(clk,rst,en,echo,trig,report,valid,cm);
 ultrasonic_pitch #(.CLOCK_HZ(1000000),.LOST_MS(250)) pitch(
  clk,rst,cfg,en,band,minimum,maximum,version,report&&report_enable,valid,cm,ratio,status,bcd,applied);
 integer checks=0,previous=0,older=0,wanted=65536,reports=0;reg have=0;
 always @(posedge report)reports++;
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 function automatic integer median(input integer a,b,c);begin
  if((a<=b&&a>=c)||(a>=b&&a<=c))median=a;
  else if((b<=a&&b>=c)||(b>=a&&b<=c))median=b;else median=c;
 end endfunction
 function automatic integer mapped(input integer d);real mid,halfspan,offset,fraction;begin
  mid=(minimum+maximum)/2.0;halfspan=(maximum-minimum)/2.0;offset=d>mid?d-mid:mid-d;
  if(d<=minimum)mapped=73562;else if(d>=maximum)mapped=58386;
  else if(offset<=band || halfspan<=band)mapped=65536;
  else begin fraction=(offset-band)/(halfspan-band);mapped=d<mid?65536+$rtoi(8026*fraction+0.5):65536-$rtoi(7150*fraction+0.5);end
 end endfunction
 task echo_pulse(input integer physical_us);integer expected,filtered,expected_bcd;bit expected_valid;begin
  @(posedge trig);@(negedge trig);clocks(17);echo=1;clocks(physical_us);echo=0;
  @(posedge report);#1;
  expected=(physical_us+29)/58;expected_valid=expected>=2&&expected<=400;
  if(cm!==expected || valid!==expected_valid)$fatal(1,"Physical pulse %0dus: got %0dcm valid%0d expected %0dcm valid%0d",physical_us,cm,valid,expected,expected_valid);
  if(expected_valid)begin
   filtered=have?median(expected,previous,older):expected;
   older=have?previous:expected;previous=expected;have=1;wanted=mapped(filtered);
  end
  clocks(32);
  if(ratio!==wanted)$fatal(1,"Real echo pitch differs cm=%0d actual%0d expected%0d",expected,ratio,wanted);
  if(expected_valid)begin
   expected_bcd=(expected/100)*256+((expected/10)%10)*16+expected%10;
   if(bcd!==expected_bcd || status!==2)$fatal(1,"Real echo cm/BCD mismatch cm%0d BCD%h",expected,bcd);
  end else if(status!==3)$fatal(1,"Invalid physical echo did not hold last sample");
  checks++;
 end endtask
 initial begin
  clocks(3);rst=0;clocks(5);
  echo_pulse(116);echo_pulse(290);echo_pulse(580);echo_pulse(1305);echo_pulse(1334);
  echo_pulse(2320);echo_pulse(5800);echo_pulse(23200);
  // Rounding boundary at exactly 10.5cm, including the formerly lost first us.
  echo_pulse(608);echo_pulse(609);echo_pulse(610);
  echo_pulse(58);echo_pulse(23258);
  // No return pulse: report must be invalid; silence in reports also returns
  // pitch to neutral by wall time, not by a fixed number of invalid reports.
  @(posedge trig);@(negedge trig);@(posedge report);#1;if(valid)$fatal(1,"Missing echo accepted");checks++;
  report_enable=0;clocks(251000);
  if(ratio!==65536 || status!==4)$fatal(1,"Stale physical sensor did not return to unbent note");checks++;
  report_enable=1;
  // A stuck-high line is invalid and cannot restart a trigger train.
  echo=1;clocks(62000);if(valid || trig)$fatal(1,"Stuck-high echo accepted/retriggered");checks++;
  en=0;echo=0;clocks(5);if(trig || valid || ratio!==65536 || status!==0)$fatal(1,"Disable did not cancel sensor and pitch");checks++;
  $display("PASS tb_ultrasonic_cm_echo checks=%0d reports=%0d",checks,reports);$finish;
 end
 initial begin #2000000000;$fatal(1,"Real cm echo chain timeout");end
endmodule
