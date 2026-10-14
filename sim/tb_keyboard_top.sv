`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_keyboard_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [15:0] pressed=0;
 tri [3:0] columns;
 wire [3:0] selected,rows;
 wire bck,ws,din,pa,db,dw,dd,dp;
 wire [5:0] leds;
 wire [3:0] flow_on=~leds[3:0];
 reg [3:0] previous_flow=4'b1110;
 integer flow_moves=0,reset_flow_moves=0;
 integer checks=0,edges=0,bitn=0,ch=0,word=0,right_word=0,nonzero=0;
 realtime last_rise=0,period;
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model model(pressed,selected,rows);
 keyboard_top #(.LED_STEP_CYCLES(4),.LOCK_N(32),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16))
  dut(.clk(clk),.rst(rst),.key_row(rows),.key_col(columns),
   .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),
   .DBG_BCK(db),.DBG_WS(dw),.DBG_DIN(dd),.DBG_PA_EN(dp),.led_n(leds));
 always @(negedge clk)begin
  `CHECK(flow_on!=0 && (flow_on&(flow_on-4'd1))==0,"one running LED independent of audio reset")
  if(leds[3:0]!=previous_flow)flow_moves=flow_moves+1;
  previous_flow=leds[3:0];
 end
 always @(bck or ws or din or pa)begin
  #0.001;`CHECK({db,dw,dd,dp}==={bck,ws,din,pa},"production GPIO mirror")
 end
 always @(negedge clk)if(!dut.audio_reset)begin
  for(integer k=0;k<4;k=k+1)begin
   `CHECK(columns[k]===1'b0 || columns[k]===1'bz,"column never drives high")
  end
  `CHECK(selected!=0 && (selected&(selected-1))==0,"one column low, others high impedance")
 end
 always @(posedge bck)if(!dut.audio_reset)begin
  `CHECK(ws==(ch==1),"board keyboard channel framing")
  if(last_rise>0)begin
   period=$realtime-last_rise;
   `CHECK(period>651.02 && period<651.07,"board keyboard BCK frequency")
  end
  last_rise=$realtime;edges=edges+1;
  word=((word<<1)|din)&65535;
  if(bitn==15)begin
   if(ch==0)right_word=word;
   else begin `CHECK(word==right_word,"stereo keyboard atomics") if(word!=0)nonzero=nonzero+1;end
   ch=1-ch;word=0;bitn=0;
  end else bitn=bitn+1;
 end
 initial begin
  #100 rst=0;wait(pa);wait(edges>=320);
  `CHECK(nonzero==0,"production top idle silence")
  pressed=16'h0200;wait(dut.gate);wait(nonzero>=20);
  `CHECK(dut.selected_key==9,"physical A4 mapping")
  `CHECK(leds[5:4]==0,"ready and pressed-note LEDs lit")
  reset_flow_moves=flow_moves;
  #3 rst=1;#1;`CHECK(!pa && !dp && din==0 && columns===4'bzzzz,"reset tri-states matrix and mutes")
  bitn=0;ch=0;word=0;last_rise=0;nonzero=0;
  #81;`CHECK(flow_moves>reset_flow_moves && leds[5:4]==2'b11,"run LEDs continue while reset clears status")
  #19 rst=0;wait(pa);wait(nonzero>=10);
  `CHECK(dut.gate && dut.selected_key==9,"vendor PLL integration resumes held key")
  $display("PASS tb_keyboard_top checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"keyboard board timeout");end
endmodule
