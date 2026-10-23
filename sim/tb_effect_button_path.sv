`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_effect_button_path;
// QUICK inserts bypass between mode changes; the independent effects
 // tests retain production-length fades and mid-wet switching coverage.
 parameter integer QUICK=0;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [3:0] buttons_n=4'hf;reg [15:0] pressed=0;
 tri [3:0] columns;wire [3:0] rows,selected;
 wire bck,ws,din,pa;wire [5:0] leds;
 integer checks=0,events=0,frames=0,prior_events;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_ENABLE(0),.BUTTON_DEBOUNCE_CYCLES(4),.BUTTON_LONG_PRESS_CYCLES(128),
  .LOCK_N(32),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.SUSTAIN(32768),.RELEASE(2))
  dut(.clk(clk),.rst(rst),.board_buttons_n(buttons_n),.key_row(rows),.key_col(columns),
   .MAX_BCLK(bck),.MAX_LRCLK(ws),.MAX_DIN(din),.MAX_SD_MODE(),.led_n(leds));
 assign pa=dut.input_ready;
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model physical_keys(pressed,selected,rows);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(!dut.underrun,"mode switching never underruns audio")
  if(dut.note_valid && dut.note_ready)events=events+1;
  if(dut.frame_ce)frames=frames+1;
 end
 task audio_cycles(input integer n);begin repeat(n)@(negedge dut.audio_clk);end endtask
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task short_effect;begin buttons_n=4'h7;audio_cycles(20);buttons_n=4'hf;audio_cycles(20);end endtask
 task long_effect;begin buttons_n=4'h7;audio_cycles(400);buttons_n=4'hf;audio_cycles(20);end endtask
 initial begin
  #100 rst=0;wait(pa);more_frames(4);
  `CHECK(dut.effect_mode==0 && !dut.effects_enabled,"reset starts in dry echo preset")
  short_effect;more_frames(QUICK?8:270);
  `CHECK(dut.effects_enabled && (QUICK?dut.sound.effect.fade_level>0:dut.sound.effect.fade_level==256),"short release enables echo and starts the fade")
  if(QUICK)begin short_effect;more_frames(16);end
  prior_events=events;long_effect;more_frames(QUICK?24:530);
  `CHECK(dut.effect_mode==1 && dut.sound.effect.active_mode==1,"long hold reaches room engine")
  `CHECK(events==prior_events && !dut.gate,"effect controls cannot create notes")
  buttons_n=4'hd;audio_cycles(20);buttons_n=4'hf;audio_cycles(20);
  pressed=16'h0200;wait(dut.gate);more_frames(20);
  `CHECK($countones(dut.voice_held)==1 && dut.sound.voice_timbres[1:0]==1,"manual flute voice starts through new effects")
  if(QUICK)begin short_effect;more_frames(64);end
  prior_events=events;long_effect;more_frames(QUICK?24:530);
  `CHECK(dut.effect_mode==2 && dut.sound.effect.active_mode==2 && dut.gate,"long hold reaches tremolo without releasing a held note")
  `CHECK(events==prior_events,"effect change does not retrigger held notes")
  if(QUICK)begin short_effect;more_frames(32);end
  long_effect;more_frames(QUICK?24:530);
  `CHECK(dut.effect_mode==0 && dut.sound.effect.active_mode==0,"third long hold returns to echo")
  short_effect;more_frames(QUICK?32:270);
  `CHECK(!dut.effects_enabled && dut.sound.effect.fade_level==0 && dut.gate,"bypass preserves held audio")
  pressed=0;wait(!dut.gate);more_frames(12);
  rst=1;#1;`CHECK(!pa && !dut.effects_enabled && dut.effect_mode==0,"global reset clears effect state")
  $display("PASS tb_effect_button_path checks=%0d",checks);$finish;
 end
 initial begin #70000000;$fatal(1,"effect button path timeout");end
endmodule
