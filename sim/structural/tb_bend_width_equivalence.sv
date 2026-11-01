`timescale 1ns/1ps
module tb_bend_width_equivalence;
 reg clk=0,rst=1,frame_ce=0,input_ready=1,blocked=0,menu_mode=0,can_open=1;
 reg snapshot_valid=1,report_valid=0,health_valid=1,ready=1,error=0,down=0,note_ready=1;
 reg [3:0] count=0;reg [15:0] x=0,y=0,resolution_x=800,resolution_y=480;
 reg [4:0] selected_timbre=5;
 wire note_valid,note_valid_old;
 wire note_on,note_on_old;
 wire [6:0] note_id,note_id_old;
 wire [6:0] note_pitch,note_pitch_old;
 wire [6:0] note_velocity,note_velocity_old;
 wire [31:0] note_fcw,note_fcw_old;
 wire [4:0] note_timbre,note_timbre_old;
 wire active,active_old;
 wire [63:0] status,status_old;
 wire [17:0] pitch_ratio,pitch_ratio_old;
 wire chorus_enabled,chorus_enabled_old;
 wire [8:0] chorus_wet,chorus_wet_old;
 wire [1:0] chorus_depth,chorus_depth_old;
 wire [1:0] chorus_rate,chorus_rate_old;
performance_control #(.GATE_FRAMES(37),.STALE_CYCLES(101)) dut(.clk(clk),.rst(rst),.frame_ce(frame_ce),.input_ready(input_ready),.blocked(blocked),.menu_mode(menu_mode),.can_open(can_open),.snapshot_valid(snapshot_valid),.report_valid(report_valid),.health_valid(health_valid),.ready(ready),.error(error),.down(down),.count(count),.x(x),.y(y),.resolution_x(resolution_x),.resolution_y(resolution_y),.selected_timbre(selected_timbre),.note_ready(note_ready),.note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_pitch(note_pitch),.note_velocity(note_velocity),.note_fcw(note_fcw),.note_timbre(note_timbre),.active(active),.status(status),.pitch_ratio(pitch_ratio),.chorus_enabled(chorus_enabled),.chorus_wet(chorus_wet),.chorus_depth(chorus_depth),.chorus_rate(chorus_rate));
performance_control_reference_94030a #(.GATE_FRAMES(37),.STALE_CYCLES(101)) ref_dut(.clk(clk),.rst(rst),.frame_ce(frame_ce),.input_ready(input_ready),.blocked(blocked),.menu_mode(menu_mode),.can_open(can_open),.snapshot_valid(snapshot_valid),.report_valid(report_valid),.health_valid(health_valid),.ready(ready),.error(error),.down(down),.count(count),.x(x),.y(y),.resolution_x(resolution_x),.resolution_y(resolution_y),.selected_timbre(selected_timbre),.note_ready(note_ready),.note_valid(note_valid_old),.note_on(note_on_old),.note_id(note_id_old),.note_pitch(note_pitch_old),.note_velocity(note_velocity_old),.note_fcw(note_fcw_old),.note_timbre(note_timbre_old),.active(active_old),.status(status_old),.pitch_ratio(pitch_ratio_old),.chorus_enabled(chorus_enabled_old),.chorus_wet(chorus_wet_old),.chorus_depth(chorus_depth_old),.chorus_rate(chorus_rate_old));

 always #5 clk=~clk;
 integer cycle=0,checks=0,seed=32'h2380beef,r;
 task compare;
  begin
   checks=checks+1;
   if({note_valid,note_on,note_id,note_pitch,note_velocity,note_fcw,note_timbre,active,status,pitch_ratio,chorus_enabled,chorus_wet,chorus_depth,chorus_rate,dut.armed,dut.contact,dut.sliding,dut.reverse,dut.previous_x,dut.previous_y,dut.pending,dut.held,dut.stale,dut.event_string,dut.target_ratio,dut.selected_sound,dut.slider_position,dut.wet_step} !== {note_valid_old,note_on_old,note_id_old,note_pitch_old,note_velocity_old,note_fcw_old,note_timbre_old,active_old,status_old,pitch_ratio_old,chorus_enabled_old,chorus_wet_old,chorus_depth_old,chorus_rate_old,ref_dut.armed,ref_dut.contact,ref_dut.sliding,ref_dut.reverse,ref_dut.previous_x,ref_dut.previous_y,ref_dut.pending,ref_dut.held,ref_dut.stale,ref_dut.event_string,ref_dut.target_ratio,ref_dut.selected_sound,ref_dut.slider_position,ref_dut.wet_step})$fatal(1,"module mismatch cycle=%0d x=%0d oldratio=%0d newratio=%0d",cycle,x,ref_dut.target_ratio,dut.target_ratio);
   for(integer s=0;s<12;s=s+1)if({dut.gates[s],dut.flash[s]} !== {ref_dut.gates[s],ref_dut.flash[s]})$fatal(1,"array mismatch cycle=%0d string=%0d",cycle,s);
  end
 endtask
 always @(posedge clk)begin #1;compare();end
 task touch(input bit d,input [15:0] px,py);
  begin @(negedge clk);report_valid=1;down=d;count=d?1:0;x=px;y=py;@(negedge clk);report_valid=0;end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  touch(0,0,0);touch(1,500,40);touch(0,0,0);touch(1,144,390);
  for(cycle=0;cycle<65536;cycle=cycle+1)begin
   @(negedge clk);x=cycle;y=390;report_valid=1;down=1;count=1;frame_ce=cycle[0];
  end
  touch(0,0,0);
  for(cycle=0;cycle<250000;cycle=cycle+1)begin
   @(negedge clk);r=$random(seed);frame_ce=(r&7)==1;report_valid=(r&3)==0;note_ready=(r&15)!=0;
   if((r&31)==3)begin x=$random(seed);y=$random(seed);count=$random(seed);down=$random(seed);end
   if((r&63)==7)begin x=$unsigned($random(seed))%800;y=$unsigned($random(seed))%480;count=1;down=1;end
   if((r&255)==11)begin ready=$random(seed);error=$random(seed);snapshot_valid=$random(seed);health_valid=$random(seed);end
   if((r&255)==19)begin input_ready=$random(seed);can_open=$random(seed);menu_mode=$random(seed);blocked=$random(seed);end
   if(cycle%1024==0)begin rst=1;end
   if(cycle%1024==2)begin rst=0;ready=1;error=0;snapshot_valid=1;health_valid=1;input_ready=1;can_open=1;menu_mode=0;blocked=0;end
   if(cycle%1024==4)begin report_valid=1;down=0;count=0;end
   if(cycle%1024==6)begin report_valid=1;down=1;count=1;x=500;y=40;end
   if(cycle%1024==8)begin report_valid=1;down=0;count=0;end
   if(cycle%1024==10)begin report_valid=1;down=1;count=1;x=144;y=390;end
  end
  @(negedge clk);$display("PASS tb_bend_width_equivalence checks=%0d",checks);$finish;
 end
 initial begin #5000000;$fatal(1,"bend equivalence timeout");end
endmodule
