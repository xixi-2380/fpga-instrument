`timescale 1ns/1ps
module tb_controls_performance;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [2:0] counter=0;always @(posedge clk)if(rst)counter<=0;else counter<=counter+1'b1;
 wire frame=counter==0;
 reg blocked=0,menu=0,can_open=1,report=0,health=1,down=0,nready=1,uv=0,spv=0;
 reg [6:0] action=63;reg [15:0] x=0,y=0;reg [17:0] sensor=65536;
 wire nv,no,active,chorus;wire [6:0] id,pitch,velocity;wire [31:0] fcw;wire [4:0] tone;wire [63:0] status;wire [17:0] ratio;wire [8:0] wet;wire [1:0] depth,rate;
 `include "config/ui_layout.svh"
 performance_control #(.GATE_FRAMES(7),.STALE_CYCLES(1000)) dut(
  .clk(clk),.rst(rst),.frame_ce(frame),.input_ready(1'b1),.blocked(blocked),.menu_mode(menu),.can_open(can_open),
  .snapshot_valid(1'b1),.report_valid(report),.health_valid(health),.ready(1'b1),.error(1'b0),.down(down),.count(4'd1),.x(x),.y(y),.resolution_x(16'd800),.resolution_y(16'd480),
  .selected_timbre(5'd15),.note_ready(nready),.note_valid(nv),.note_on(no),.note_id(id),.note_pitch(pitch),.note_velocity(velocity),.note_fcw(fcw),.note_timbre(tone),
  .active(active),.status(status),.pitch_ratio(ratio),.chorus_enabled(chorus),.chorus_wet(wet),.chorus_depth(depth),.chorus_rate(rate),
  .ui_action_valid(uv),.ui_action(action),.sensor_pitch_ratio(sensor),.sensor_pitch_valid(spv));
 integer checks=0,expected_ratio=65536,expected_target=65536,ons=0,offs=0;
 reg stalled=0;reg [58:0] previous;
 always @(posedge clk)begin
  if(rst)begin expected_ratio=65536;expected_target=65536;stalled=0;end
  else begin
   if(frame)begin
    if(expected_ratio<expected_target)expected_ratio=expected_target-expected_ratio>32?expected_ratio+32:expected_target;
    else if(expected_ratio>expected_target)expected_ratio=expected_ratio-expected_target>32?expected_ratio-32:expected_target;
   end
   expected_target=spv&&!blocked&&!menu?sensor:65536;
   if(stalled && (!nv || {no,id,pitch,velocity,fcw,tone}!==previous))$fatal(1,"Harp payload changed while allocator busy");
   previous={no,id,pitch,velocity,fcw,tone};stalled=nv&&!nready;
   if(nv && nready)begin
    if(id<96 || id>107 || velocity!=100)$fatal(1,"Harp identity/velocity out of range");
    if(no)ons++;else offs++;
   end
   #0.001;if(ratio!==expected_ratio)$fatal(1,"Pitch slew or sensor-only source mismatch got=%0d expected=%0d",ratio,expected_ratio);checks++;
  end
 end
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task tap(input [6:0] a);begin action=a;uv=1;clocks(1);uv=0;clocks(1);end endtask
 task touch(input integer xx,yy,input bit d);begin x=xx;y=yy;down=d;report=1;clocks(1);report=0;clocks(3);end endtask
 initial begin
  clocks(3);rst=0;clocks(5);tap(UI_HARP_OPEN);if(!active)$fatal(1,"UI harp open failed");
  // The retired screen slider cannot influence pitch, even on its endpoints.
  for(integer n=0;n<100;n++)begin touch(n%2==0?144:656,384,1);if(ratio!=65536)$fatal(1,"Old screen slider changed pitch");end
  touch(400,384,0);spv=1;sensor=73562;clocks(2200);if(ratio!=73562)$fatal(1,"Near sensor endpoint not reached");
  sensor=58386;clocks(4000);if(ratio!=58386)$fatal(1,"Far sensor endpoint not reached");
  spv=0;sensor=0;clocks(2000);if(ratio!=65536)$fatal(1,"Invalid sensor did not smoothly return neutral");
  spv=1;sensor=70000;menu=1;clocks(20);if(active)$fatal(1,"Menu did not close harp");menu=0;tap(UI_HARP_OPEN);
  tap(UI_CHORUS);if(!chorus)$fatal(1,"UI chorus failed");tap(UI_CHORUS_MIX);if(wet!=128)$fatal(1,"Chorus mix4 failed");tap(UI_CHORUS_MIX);if(wet!=32)$fatal(1,"Chorus mix wrap failed");
  tap(UI_CHORUS_DEPTH);tap(UI_CHORUS_DEPTH);if(depth!=0)$fatal(1,"Chorus depth wrap failed");
  tap(UI_CHORUS_RATE);tap(UI_CHORUS_RATE);if(rate!=0)$fatal(1,"Chorus rate wrap failed");
  touch(112,250,0);nready=0;touch(112,250,1);clocks(10);if(!nv || !no)$fatal(1,"Touch pluck was not offered");
  tap(UI_HARP_BACK);clocks(100);if(active || !nv)$fatal(1,"Leaving page withdrew an in-flight pluck");
  nready=1;clocks(120);if(ons!=offs || dut.held!=0)$fatal(1,"Page exit did not drain accepted harp Off");
  tap(UI_HARP_OPEN);tap(UI_HARP_TONE);
  for(integer k=0;k<12;k++)begin touch(112+k*48,250,0);touch(112+k*48,250,1);clocks(70);end
  tap(UI_HARP_BACK);clocks(150);if(ons!=offs || ons<13)$fatal(1,"Twelve strings did not balance their releases");
  if(tone!=15)$fatal(1,"Harp did not use selected panel tone");
  $display("PASS tb_controls_performance checks=%0d ons=%0d offs=%0d",checks,ons,offs);$finish;
 end
 initial begin #1000000;$fatal(1,"Performance control timeout");end
endmodule
