`timescale 1ns/1ps
`include "check.svh"
`include "touch_keyboard_fixture.svh"
module tb_touch_ec11_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [2:0] a=7,b=7,sw=7;reg [35:0] pressed=0;reg [11:0] auxiliary=0;reg [2:0] present=7;
 tri1 [2:0] scl,sda;wire [2:0] int_n;
 integer checks=0,frames=0,frame_cycle=0,cycles_count=0,max_delivery=0;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),
  .MUTE(2),.FADE(2),.ATTACK(2),.DECAY(2),.RELEASE(2),.SUSTAIN(32768),
  .KEYPAD_BOOT_CYCLES(20),.KEYPAD_POLL_CYCLES(1600),.KEYPAD_I2C_HALF(4),.KEYPAD_TIMEOUT_CYCLES(100),.KEYPAD_RETRY_CYCLES(32),
  .EC11_MS_CYCLES(8),.EC11_FILTER_CYCLES(2),.EC11_DEBOUNCE_MS(2),.EC11_DOUBLE_MS(12),.EC11_LONG_MS(30)) dut(
  .clk(clk),.rst(rst),.bt_rx(1'b1),.ultrasonic_echo(1'b0),.board_buttons_n(4'hf),
  .keypad_scl(scl),.keypad_sda(sda),.keypad_int_n(int_n),.ec11_a(a),.ec11_b(b),.ec11_sw_n(sw));
 touch_keyboard_fixture keyboard(rst,pressed,auxiliary,present,scl,sda,int_n);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  cycles_count=cycles_count+1;
  `CHECK(!dut.underrun,"stacked effects and encoder updates never underrun")
  if(dut.frame_ce)begin frames=frames+1;frame_cycle=cycles_count;end
  if(dut.sound.effect_valid)begin
   if(cycles_count-frame_cycle>max_delivery)max_delivery=cycles_count-frame_cycle;
   `CHECK(cycles_count-frame_cycle<=544,"all three serial stages finish within existing render budget")
  end
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.audio_clk);end endtask
 task more(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task turn(input integer i);begin
  a[i]=0;cycles(12);b[i]=0;cycles(12);a[i]=1;cycles(12);b[i]=1;cycles(12);
 end endtask
 task click(input integer i);begin sw[i]=0;cycles(32);sw[i]=1;cycles(32);end endtask
 task one(input integer i);begin click(i);cycles(160);end endtask
 task two(input integer i);begin click(i);click(i);cycles(160);end endtask
 initial begin
  #100;rst=0;wait(dut.input_ready && dut.keypad_online==7);more(4);
  `CHECK(dut.effect_mask==0 && !dut.ultrasonic_trig,"startup retains dry/manual default")
  auxiliary=12'hfff;wait(dut.auxiliary_keys==12'hfff);more(3);
  `CHECK(!dut.aux_action_valid && !dut.menu_mode && !dut.more_open && !dut.ultrasonic_page &&
    dut.selected_timbre==0 && dut.volume_percent==100 && dut.effect_mask==0,
    "production default ignores all twelve AUX controls without changing settings")
  auxiliary=0;wait(dut.auxiliary_keys==0);more(2);
  turn(0);cycles(8);`CHECK(dut.echo_time_ms==160 && dut.cfg_echo_samples==7680 && dut.effect_mask==0,"physical echo A/B changes time without enabling")
  one(0);turn(0);`CHECK(dut.echo_edit_strength && dut.echo_percent==26,"physical single click changes echo control to amount")
  two(0);two(1);two(2);cycles(20);
  `CHECK(dut.effect_mask==7 && dut.cfg_effect_mask==7 && dut.echo_edit_strength && !dut.tremolo_edit_rate,"three physical double clicks enable all, without singles")
  turn(1);turn(2);`CHECK(dut.room_percent==26 && dut.depth_percent==51,"each physical knob adjusts its own amount")
  one(2);turn(2);`CHECK(dut.tremolo_edit_rate && dut.tremolo_rate_hz==6,"tremolo single click selects rate")
  sw[0]=0;cycles(32);turn(0);sw[0]=1;cycles(200);
  `CHECK(dut.echo_edit_strength && dut.echo_percent==27,"turning a pressed physical knob cannot cause a click mode change")
  pressed=1;wait(dut.gate);more(330);
  `CHECK($countones(dut.voice_held)==1 && dut.visual_notes==1 && dut.sound.release_strength==69 && dut.sound.effect.echo_level==0 && dut.sound.effect.room_level==67,"stacked stages and one-key ownership both active")
  `CHECK(dut.sound.effect.depth_level==131 && dut.sound.effect.phase_step==536871,"independent tremolo depth/rate reach running DSP")
  two(1);more(300);`CHECK(dut.effect_mask==5 && dut.sound.effect.room_level==0 && dut.sound.release_strength==69 && dut.sound.effect.echo_level==0,"disabling room preserves other running effects")
  // Three independent buses deliver simultaneous chords and the highest B6.
  pressed=(36'd1<<0)|(36'd1<<12)|(36'd1<<35);wait($countones(dut.voice_held)==3);more(4);
  `CHECK(dut.visual_notes==pressed,"all three boards and B6 reach physical voice metadata and display")
  present[1]=0;wait(!dut.keypad_online[1]);wait($countones(dut.voice_held)==2);
  `CHECK(dut.visual_notes[35] && dut.visual_notes[0],"one offline board cannot release other boards")
  present[1]=1;wait(dut.keypad_online==7);more(5);
  `CHECK($countones(dut.voice_held)==2,"held key on reconnect must release before rearming")
  pressed[12]=0;more(4);pressed[12]=1;wait($countones(dut.voice_held)==3);
  two(0);two(2);pressed=0;more(350);
  `CHECK(dut.effect_mask==0 && dut.voice_active==0 && dut.visual_sample==0,"all effects bypass and released keyboard return to exact silence")
  `CHECK(dut.MAX_SD_MODE && dut.PA_EN==0 && dut.HP_BCK==0,"MAX audio clock/startup and retired pins preserved")
  $display("PASS tb_touch_ec11_top checks=%0d frames=%0d max_delivery=%0d",checks,frames,max_delivery);$finish;
 end
 initial begin #50000000;$fatal(1,"EC11 top timeout");end
endmodule
