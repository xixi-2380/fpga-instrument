`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_keyboard_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [15:0] pressed=0;reg [3:0] buttons_n=4'hf;
 tri [3:0] columns;
 wire [3:0] selected,rows;
 wire bck,ws,din,pa,db,dw,dd,dp;
 wire [5:0] leds;
 wire [3:0] flow_on=~leds[3:0];
 reg [3:0] previous_flow=4'b1110;
 integer flow_moves=0,reset_flow_moves=0,idle_edge_start,diag_heartbeat,stage=0;
 reg pair_check=0;
 integer checks=0,edges=0,bitn=0,ch=0,word=0,right_word=0,nonzero=0;
 reg rx_synced=0,previous_ws=1;
 realtime last_rise=0,period;
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model model(pressed,selected,rows);
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.BUTTON_DEBOUNCE_CYCLES(4),.BUTTON_LONG_PRESS_CYCLES(128),.SCORE_ENABLE(0),.LED_STEP_CYCLES(4),.LOCK_N(32),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16))
  dut(.clk(clk),.rst(rst),.board_buttons_n(buttons_n),.key_row(rows),.key_col(columns),
   .MAX_BCLK(bck),.MAX_LRCLK(ws),.MAX_DIN(din),.MAX_SD_MODE(),
   .HP_BCK(),.HP_WS(),.HP_DIN(),.PA_EN(),
   .DBG_BCK(db),.DBG_WS(dw),.DBG_DIN(dd),.DBG_PA_EN(dp),.led_n(leds));
 assign pa=dut.input_ready;
 always @(negedge clk)begin
  if(!dut.status_leds.diagnostic_active)begin
   `CHECK(flow_on!=0 && (flow_on&(flow_on-4'd1))==0,"one running LED outside startup diagnosis")
  end
  if(leds[3:0]!=previous_flow)flow_moves=flow_moves+1;
  previous_flow=leds[3:0];
 end
 always @(bck or ws or din or pa)begin
  #0.001;`CHECK({dut.HP_BCK,dut.HP_WS,dut.HP_DIN,dut.PA_EN,db,dw,dd,dp}===8'b0,
   "board DAC, amplifier and old debug outputs remain disabled")
 end
 always @(negedge clk)if(!dut.audio_reset)begin
  for(integer k=0;k<4;k=k+1)begin
   `CHECK(columns[k]===1'b0 || columns[k]===1'bz,"column never drives high")
  end
  `CHECK(selected!=0 && (selected&(selected-1))==0,"one column low, others high impedance")
 end
 always @(posedge bck)if(!dut.audio_reset)begin
  if(last_rise>0)begin
   period=$realtime-last_rise;
   `CHECK(period>651.02 && period<651.07,"board keyboard BCK frequency")
  end
  last_rise=$realtime;edges=edges+1;
  if(!rx_synced)begin
   if(ws!=previous_ws)begin rx_synced=1;ch=ws;bitn=0;word=0;end
  end else begin
  word=((word<<1)|din)&65535;
  if(bitn==15)begin
   `CHECK(ws!=previous_ws && ws!=ch,"board I2S transition carries old channel LSB")
   if(pair_check)begin `CHECK($signed(word[15:0])>=-2048 && $signed(word[15:0])<=2047,
    "physical two-key transient stays within two voices of gain") end
   if(ch==0)right_word=word;
   else begin `CHECK(word==right_word,"stereo keyboard atomics") if(word!=0)nonzero=nonzero+1;end
   ch=ws;word=0;bitn=0;
  end else begin `CHECK(ws==previous_ws,"I2S channel length") bitn=bitn+1;end
  end
  previous_ws=ws;
 end
 initial begin
  #100 rst=0;wait(pa);wait(edges>=320);stage=1;
  `CHECK(nonzero==0,"production top idle silence")
  pressed=16'h0200;wait(dut.gate);wait(nonzero>=20);stage=2;
  `CHECK(dut.last_key==9,"physical A4 mapping")
  `CHECK(leds[5:4]==0,"ready and pressed-note LEDs lit")
  reset_flow_moves=flow_moves;
  #3 rst=1;#1;`CHECK(!pa && !dp && din==0 && columns===4'bzzzz,"reset tri-states matrix and mutes")
  rx_synced=0;previous_ws=1;bitn=0;ch=0;word=0;last_rise=0;nonzero=0;
  #81;`CHECK(flow_moves>reset_flow_moves && leds[5:4]==2'b11,"run LEDs continue while reset clears status")
  #19 rst=0;wait(pa);repeat(320)@(posedge bck);
  `CHECK(!dut.gate && dut.inhibit_notes,"reset-held key stays inhibited until a full release")
  pressed=0;wait(!dut.inhibit_notes);pressed=16'h0200;wait(dut.gate);wait(nonzero>=10);stage=3;
  `CHECK(dut.gate && dut.last_key==9,"vendor PLL integration rearms after release and resumes the key")
  // Verify real serial idle behavior before attributing audible hiss to analog hardware.
  pressed=0;wait(!dut.gate);wait(dut.envelope_level==0);
  repeat(64)@(posedge bck);#0.002;nonzero=0;idle_edge_start=edges;
  wait(edges>=idle_edge_start+640);#0.002;
  `CHECK(nonzero==0,"released voice sends zero on both channels for twenty frames") stage=4;
  `CHECK(pa && leds[5],"existing idle behavior keeps amplifier enabled while note LED is off")
  // Four physical keys sharing one column are unambiguous without diodes.
  pressed=16'h1111;wait(dut.voice_held==4'hf);repeat(32*24)@(posedge bck);#0.002;
  `CHECK(dut.voice_active==4'hf,"vendor PLL board sustains four physical voices") stage=5;
  pressed=16'h1101;wait($countones(dut.voice_held)==3);repeat(32*24)@(posedge bck);#0.002;
  `CHECK($countones(dut.voice_active)==3,"board release preserves three held voices") stage=6;
  pressed=0;wait(!dut.gate);wait(dut.envelope_level==0);
  repeat(64)@(posedge bck);#0.002;nonzero=0;idle_edge_start=edges;
  wait(edges>=idle_edge_start+320);#0.002;
  `CHECK(nonzero==0 && pa,"polyphonic Release returns to zero with original PA policy") stage=7;
  // Physical ordinary two-key attacks in every preset. Selection remains in
  // matrix menu; selecting a preset must never generate notes.
  for(integer preset=0;preset<3;preset=preset+1)begin
   stage=10+preset;
   if(preset>0)begin
    buttons_n=4'he;repeat(260)@(negedge dut.audio_clk);buttons_n=4'hf;repeat(16)@(negedge dut.audio_clk);
    pressed=16'b1<<preset;repeat(32*8)@(posedge bck);pressed=0;repeat(32*8)@(posedge bck);
    pressed=16'h8000;repeat(32*8)@(posedge bck);pressed=0;repeat(32*8)@(posedge bck);
    `CHECK(dut.selected_timbre==preset && !dut.menu_mode,"matrix menu selects requested preset")
    `CHECK(!dut.gate && dut.voice_active==0,"preset button does not create notes")
    repeat(64)@(posedge bck);
   end
   pair_check=1;pressed=16'h0003;
   wait($countones(dut.voice_held)==2);repeat(32*24)@(posedge bck);
   `CHECK($countones(dut.voice_active)==2,"all presets sustain a physical ordinary two-key chord")
   pressed=0;wait(!dut.gate);wait(dut.envelope_level==0);
   repeat(64)@(posedge bck);pair_check=0;
  end
  stage=20;
  // Simulate persistent PLL2 failure; diagnostics must work from the reference domain.
  force dut.lock2=1'b0;#1;
  `CHECK(dut.audio_reset && !pa,"PLL loss still immediately resets and mutes audio")
  rx_synced=0;previous_ws=1;bitn=0;ch=0;word=0;last_rise=0;nonzero=0;
  repeat(40)@(negedge clk);
  `CHECK(dut.status_leds.diagnostic_active,"board enters delayed PLL status diagnostics")
  `CHECK(leds[3:1]==3'b110 && leds[5:4]==2'b11,"board shows PLL1 lock, PLL2 failure, no external reset")
  diag_heartbeat=leds[0];repeat(4)@(negedge clk);
  `CHECK(leds[0]!=diag_heartbeat,"diagnostic heartbeat survives stalled audio domain")
  release dut.lock2;wait(pa);repeat(4)@(negedge clk);stage=21;
  `CHECK(!dut.status_leds.diagnostic_active && !leds[4],"qualified PLL recovery restores running lights")
  `CHECK(nonzero==0,"recovered idle stream stays zero")
  // Reproduce the reported diagnostic state with a persistently high reset input.
  #3 rst=1;#1;stage=22;
  `CHECK(!pa && din==0 && columns===4'bzzzz,"held reset immediately mutes and releases matrix")
  rx_synced=0;previous_ws=1;bitn=0;ch=0;word=0;last_rise=0;nonzero=0;
  repeat(40)@(negedge clk);
  `CHECK(dut.status_leds.diagnostic_active && !leds[3],"persistent high USR lights reset diagnostic LED")
  `CHECK(leds[2:1]==2'b11 && leds[5:4]==2'b11,"held reset keeps PLL lock, ready and note LEDs off")
  `CHECK(dut.pll1_reset && dut.pll2_reset && dut.audio_reset,"reset is not bypassed or timed out")
  diag_heartbeat=leds[0];repeat(4)@(negedge clk);
  `CHECK(leds[0]!=diag_heartbeat,"reference heartbeat continues with USR stuck high")
  rst=0;wait(pa);repeat(4)@(negedge clk);stage=23;
  `CHECK(!dut.audio_reset && !leds[4] && !dut.status_leds.diagnostic_active,"released USR restores qualified startup")
  pressed=16'h0200;wait(dut.gate);wait(nonzero>=10);
  `CHECK(dut.last_key==9 && !leds[5],"keyboard and serial audio recover after released USR")
  $display("PASS tb_keyboard_top checks=%0d",checks);$finish;
 end
 initial begin #10000000;
  $display("KEYBOARD_TIMEOUT stage=%0d edges=%0d nonzero=%0d gate=%b active=%h held=%h ready=%b reset=%b",
   stage,edges,nonzero,dut.gate,dut.voice_active,dut.voice_held,pa,dut.audio_reset);
  $fatal(1,"keyboard board timeout");
 end
endmodule

