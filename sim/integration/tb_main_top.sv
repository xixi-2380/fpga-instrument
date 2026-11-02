`timescale 1ns/1ps
`include "touch_keyboard_fixture.svh"
module tb_main_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [2:0] a=7,b=7,sw=7,present=7;reg [35:0] pressed=0;
 tri1 [2:0] scl,sda;wire [2:0] intr;
 reg [72:0] touch=0;reg upd=0,takeover=0,clear=0;
 reg [40:0] sensor=0;reg sensor_valid=0;
 integer checks=0,ons=0,offs=0,harp_ons=0,harp_offs=0;
 wire probe;
 reg [35:0] probe_seen=0,probe_qualified;
 integer ref_tick=0,probe_last=-100000,probe_events=0;
 keyboard_top #(.BT_ENABLE(0),.LCD_ENABLE(0),.TOUCH_ENABLE(1),.LOCK_N(16),.MUTE(1),.FADE(1),
  .ATTACK(2),.DECAY(2),.RELEASE(4),.KEYPAD_BOOT_CYCLES(20),.KEYPAD_POLL_CYCLES(1600),
  .KEYPAD_I2C_HALF(4),.KEYPAD_TIMEOUT_CYCLES(100),.KEYPAD_RETRY_CYCLES(32),.KEYPAD_STALE_CYCLES(80000),
  .PCB_COMMAND_TIMEOUT_CYCLES(200000),.EC11_MS_CYCLES(8),.EC11_FILTER_CYCLES(2),.EC11_DEBOUNCE_MS(2),
  .EC11_DOUBLE_MS(12),.EC11_LONG_MS(30)) dut(
   .clk(clk),.rst(rst),.bt_rx(1'b1),.ultrasonic_echo(1'b0),.keypad_scl(scl),.keypad_sda(sda),.keypad_int_n(intr),
   .ec11_a(a),.ec11_b(b),.ec11_sw_n(sw),.KEY_INPUT_PROBE(probe));
 defparam dut.performance.GATE_FRAMES=16;
 touch_keyboard_fixture keyboard(rst,pressed,12'd0,present,scl,sda,intr);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 // Observe the real I2C scan path, before the audio CDC and voice admission.
 always @(posedge clk)begin
  ref_tick++;
  if(dut.ultrasonic_ref_reset)begin probe_seen=0;probe_last=-100000;end
  else begin
   for(integer k=0;k<36;k++)probe_qualified[k]=dut.keypad_ref_keys[(k/12)*16+k%12] && dut.keypad_ref_online[k/12] && dut.keypad_ref_valid[k/12];
   if((probe_qualified&~probe_seen)!=0)begin probe_last=ref_tick;probe_events++;end
   probe_seen=probe_qualified;
  end
  #1;
  if(probe!==(!dut.ultrasonic_ref_reset && ref_tick-probe_last<50000))$fatal(1,"W25 differs from qualified keyboard detection/pulse duration");
 end
 task frames(input integer n);repeat(n)begin @(posedge dut.audio_clk);while(!dut.frame_ce)@(posedge dut.audio_clk);@(negedge dut.audio_clk);end endtask
 task held_count(input integer n);integer j;begin
  j=0;while($countones(dut.voice_held)!=n && j<120)begin frames(1);j++;end
  check($countones(dut.voice_held)==n,$sformatf("held count expected%0d got%0d",n,$countones(dut.voice_held)));
 end endtask
 task report(input bit down,input integer x,y);begin
  @(negedge dut.audio_clk);touch={~touch[72],~touch[71],16'd800,16'd480,1'b1,1'b0,down,down?4'd1:4'd0,16'(x),16'(y)};upd=1;
  @(negedge dut.audio_clk);upd=0;repeat(5)@(negedge dut.audio_clk);
 end endtask
 task tap(input integer x,y);begin report(0,0,0);report(1,x,y);report(0,0,0);end endtask
 task cycles(input integer n);repeat(n)@(negedge dut.audio_clk);endtask
 task turn_up(input integer e);begin a[e]=0;cycles(12);b[e]=0;cycles(12);a[e]=1;cycles(12);b[e]=1;cycles(12);end endtask
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  if(dut.note_valid && dut.note_ready)begin
   if(dut.note_on)ons++;else offs++;
   if(dut.note_id>=96)begin if(dut.note_on)harp_ons++;else harp_offs++;end
  end
  if(dut.frame_ce)check(!dut.underrun,"production filtered stereo has no underrun");
 end
 initial begin
  force dut.touch_audio=touch;force dut.touch_audio_valid=1'b1;force dut.touch_update=upd;
  force dut.bt_inhibit=takeover;force dut.bt_flush=clear;
  force dut.ultrasonic_result=sensor;force dut.ultrasonic_result_valid=sensor_valid;
  #100 rst=0;wait(dut.input_ready && dut.keypad_online==7 && dut.keypad_data_valid==7);frames(3);
  check(dut.voice_held==0 && !dut.score_busy,"startup is silent, no ROM autoplay");
  check(dut.volume_percent==100 && dut.effect_mask==0,"initial volume and dry controls");
  tap(90,442);tap(230,442);tap(370,442);tap(520,442);
  check(dut.view_mode==1 && dut.language_zh && dut.theme_id==3,"touch view/language/theme/egg actions reach top");
  tap(520,442);check(dut.theme_id==1,"touch exits egg to previous regular theme");
  pressed[0]=1;held_count(1);tap(710,40);held_count(0);
  check(dut.menu_mode,"touch enters settings and releases held key");
  tap(334,320);check(dut.volume_percent==95,"screen volume remains available");
  turn_up(1);cycles(4);check(dut.volume_percent==96 && dut.room_percent==25 && dut.effect_mask==0,"second physical knob changes only master volume");
  tap(690,402);check(dut.sensitivity_open,"simple sensitivity page opens");
  tap(710,205);tap(710,286);tap(500,370);
  wait(dut.sensitivity_status[12]);wait(!dut.sensitivity_status[12]);
  check(dut.sensitivity_status[14] && !dut.sensitivity_status[13],"all three real I2C models verified global configuration");
  check(keyboard.boards[0].chip.registers[32]==3 && keyboard.boards[1].chip.registers[32]==3 && keyboard.boards[2].chip.registers[32]==3,"global GSR written to every board");
  for(integer k=0;k<16;k++)check(keyboard.boards[0].chip.registers[k]==5 && keyboard.boards[1].chip.registers[k]==5 && keyboard.boards[2].chip.registers[k]==5,"global KOR written to all channels");
  tap(710,40);tap(710,40);pressed=0;frames(5);pressed=(36'd1<<0)|(36'd1<<12)|(36'd1<<35);held_count(3);
  present[1]=0;wait(!dut.keypad_online[1]);held_count(2);present[1]=1;wait(dut.keypad_online==7);frames(5);
  check($countones(dut.voice_held)==2,"held key cannot resurrect after board reconnect");
  pressed[12]=0;frames(4);pressed[12]=1;held_count(3);pressed=0;held_count(0);
  tap(500,40);check(dut.performance_active,"touch opens harp without a Dock button");
  pressed[0]=1;held_count(1);report(1,112,260);report(1,640,260);frames(8);
  check(harp_ons==12 && $countones(dut.voice_held)==13,"twelve touch strings coexist with physical key");
  report(0,0,0);frames(20);check(harp_offs==12 && $countones(dut.voice_held)==1,"harp releases independently");
  tap(740,128);check(dut.chorus_enabled,"HARP page Chorus button remains functional");
  tap(640,390);frames(2);check(dut.manual_pitch_ratio==65536,"retired screen slider cannot bend pitch");
  tap(710,40);tap(710,40);tap(530,402);tap(620,125);tap(710,40);tap(710,40);
  check(dut.ultrasonic_enabled && !dut.menu_mode,"ultrasonic pitch enabled through screen");
  pressed=0;frames(4);pressed[0]=1;held_count(1);
  sensor={dut.ultrasonic_version,18'd73562,3'd2,12'h050};sensor_valid=1;frames(260);
  check(dut.manual_pitch_ratio==73562 && dut.volume_percent==96,"ultrasonic ratio bends held note without changing volume");
  sensor_valid=0;frames(260);check(dut.manual_pitch_ratio==65536,"invalid sensor state recentres smoothly");
  takeover=1;frames(2);check(dut.key_events.reported_keys[0],"source admission alone does not erase accepted manual bookkeeping");
  clear=1;frames(3);check(dut.voice_held==0 && !dut.key_events.reported_keys[0],"engine flush and adapter clear agree");
  takeover=0;clear=0;pressed=0;report(0,0,0);frames(5);pressed[0]=1;held_count(1);pressed[0]=0;held_count(0);frames(8);
  check(dut.voice_active==0 && dut.MAX_SD_MODE,"released voices terminate; audio clocks keep running");
  check(probe_events>=8,"W25 observes physical presses across all three boards and menu/admission changes");
  $display("PASS tb_main_top checks=%0d ons=%0d offs=%0d harp_on=%0d harp_off=%0d probe_events=%0d",checks,ons,offs,harp_ons,harp_offs,probe_events);$finish;
 end
 initial begin #150000000;$fatal(1,"main top timeout");end
endmodule
