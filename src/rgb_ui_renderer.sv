`timescale 1ns/1ps
// British black/gold UI. Layout, glyph/ROM and output are three pixel stages.
// One atomic1133-bit snapshot per frame; no framebuffer and no audio stalls.
module rgb_ui_renderer(
 input wire pixel_clk,rst,frame_start,status_valid,input wire [1132:0] status_data,
 input wire [10:0] x,y,input wire de_in,hs_in,vs_in,
 output reg [23:0] rgb,output reg de_out,hs_out,vs_out);
 `include "config/ui_layout.svh"
 localparam [23:0] BG=24'h101214,PANEL=24'h191c20,GOLD=24'hd6b979,
  CREAM=24'hf2e6c9,INK=24'h17191b,DIM=24'h9c987f,LINE=24'h4b4534,
  WINE=24'h67333e,GREEN=24'h8bc79b,RED=24'hef8f85;
 reg [1132:0] state;
 wire [19:0] latency=state[1131:1112];
 wire [2:0] timbre={state[53],state[13:12]};
 wire [1:0] fx=state[22:21];wire menu=state[20],enabled=state[23];
 wire [6:0] percent=fx==0 ? state[30:24] : fx==1 ? state[37:31] : state[44:38];
 wire [3:0] rate=state[48:45];
 wire [6:0] volume=state[60:54];
 wire [5:0] voices=state[5:0]>32 ? 6'd32 : state[5:0];
 wire [7:0] peak=state[87:80];
 reg [23:0] base,fg,base_pipe,fg_pipe;
 reg [319:0] text;
 reg [5:0] len,ci;
 reg [10:0] tx,ty;
 reg signed [11:0] dx,dy;
 integer px,py,i,k,left,top,note_index;
 reg [6:0] bin;
 integer point_y,previous_y,minimum_y,maximum_y,pc;
 reg [7:0] ch;reg [11:0] font_addr;reg [3:0] font_bit,bit_pipe;
 reg text_ink,ink_pipe,de_pipe,hs_pipe,vs_pipe;
 reg [7:0] glyph_char;
 reg [319:0] glyph_text;reg [5:0] glyph_len;
 reg signed [11:0] glyph_dx,glyph_dy;
 reg glyph_title,glyph_allow;
 reg [11:0] title_address;
 reg [3:0] title_bit;
 reg [23:0] base_layout,fg_layout;
 reg de_layout,hs_layout,vs_layout;
 always @*begin
  font_addr=0;font_bit=0;text_ink=0;ci=0;glyph_char=0;
  if(glyph_allow && glyph_len>0 && glyph_dx>=0 && glyph_dx<glyph_len*12'd10 && glyph_dy>=0 && glyph_dy<16)begin
   ci=glyph_dx/12'd10;glyph_char=glyph_text[(glyph_len-6'd1-ci)*8+:8];
   if(glyph_char>=32 && glyph_char<128)begin font_addr=(glyph_char-8'd32)*12'd16+glyph_dy;font_bit=15-(glyph_dx%12'd10);text_ink=1;end
  end
  if(glyph_title)begin font_addr=title_address;font_bit=title_bit;text_ink=1;end
 end
 reg [15:0] font_rom[0:4095],font_row;
 initial $readmemh("src/rom/british_font.hex",font_rom);
 function automatic [7:0] digit(input integer value);
  begin digit=8'd48+value;end
 endfunction
 function automatic [79:0] timbre_name(input [2:0] id);
  begin case(id)
   1:timbre_name="FLUTE";2:timbre_name="REED";3:timbre_name="CELLO";
   4:timbre_name="PIANO";5:timbre_name="GUITAR";6:timbre_name="VIBRAPHONE";
   default:timbre_name="SINE";endcase end
 endfunction
 function automatic integer name_length(input [2:0] id);
  begin case(id)1,3,4:name_length=5;2,0:name_length=4;5:name_length=6;default:name_length=10;endcase end
 endfunction
 function automatic [23:0] card(input integer xx,yy,l,t,w,h,input selected);
  begin
   card=selected ? CREAM : PANEL;
   if(xx<l+1 || xx>=l+w-1 || yy<t+1 || yy>=t+h-1)card=selected ? GOLD : LINE;
  end
 endfunction
 always @*begin
  px=integer'(x);py=integer'(y);base=BG;fg=CREAM;text=0;len=0;tx=0;ty=0;
  dx=0;dy=0;i=0;k=0;left=0;top=0;note_index=0;pc=0;
  bin=0;point_y=234;previous_y=234;minimum_y=234;maximum_y=234;
  ch=0;
  // Sparse faint celestial motifs. Ornament is kept outside touch controls.
  if((py==78 && px>=20 && px<780) || (py==410 && px>=20 && px<780))base=LINE;
  if(px>398 && px<632 && py<72)begin
   if((px==412 && py>=6 && py<=14) || (py==10 && px>=408 && px<=416) ||
      (px==628 && py>=60 && py<=68) || (py==64 && px>=624 && px<=632))base=GOLD;
  end
  if(ui_inside(px,py,648,16,132,48))base=card(px,py,648,16,132,48,1'b0);
  if(menu)begin
   if(ui_inside(px,py,20,92,260,310) || ui_inside(px,py,296,92,484,88) ||
      ui_inside(px,py,296,194,484,102) || ui_inside(px,py,296,306,484,96))base=PANEL;
   for(i=0;i<7;i=i+1)begin
    left=timbre_x(i);top=timbre_y(i);
    if(ui_inside(px,py,left,top,112,52))begin
     base=card(px,py,left,top,112,52,timbre==i);
     fg=timbre==i ? INK : CREAM;text=timbre_name(i);len=name_length(i);
     tx=left+(112-len*10)/2;ty=top+18;
    end
   end
   if(ui_inside(px,py,152,324,112,52))begin
    base=card(px,py,152,324,112,52,enabled);fg=enabled ? INK : DIM;
    text=enabled ? "FX ON" : "FX OFF";len=enabled ? 5 : 6;tx=enabled ? 183 : 178;ty=342;
   end
   for(i=0;i<3;i=i+1)begin
    left=308+156*i;
    if(ui_inside(px,py,left,124,148,48))begin
     base=card(px,py,left,124,148,48,fx==i);fg=fx==i ? INK : CREAM;
     text=i==0 ? "ECHO" : i==1 ? "ROOM" : "TREMOLO";len=i==2 ? 7 : 4;
     tx=left+(148-len*10)/2;ty=140;
    end
   end
   if(ui_inside(px,py,308,240,52,48) || ui_inside(px,py,716,240,52,48) ||
      (fx==2 && (ui_inside(px,py,308,344,52,48) || ui_inside(px,py,716,344,52,48))))begin
    left=px<400 ? 308 : 716;top=py<300 ? 240 : 344;
    base=card(px,py,left,top,52,48,1'b0);fg=GOLD;text=px<400 ? "-" : "+";len=1;tx=left+21;ty=top+16;
   end
   if(px>=380 && px<680 && py>=260 && py<270)base=(px-380)<integer'(percent)*3 ? GOLD : BG;
   if(fx==2 && px>=380 && px<680 && py>=366 && py<376)base=(px-380)<integer'(rate)*30 ? WINE : BG;
   if(py>=98 && py<118)begin
    if(px<280)begin text="Timbre";len=6;tx=32;ty=100;fg=GOLD;end
    else begin text="Effect";len=6;tx=308;ty=100;fg=GOLD;end
   end
   if(py>=208 && py<228 && px>=308)begin
    ty=210;fg=GOLD;
    if(px<536)begin text=fx==2 ? "DEPTH" : "AMOUNT";len=fx==2 ? 5 : 6;tx=308;end
    else begin text={(percent==100 ? 8'd49 : 8'd32),(percent>=10 ? digit((percent/10)%10) : 8'd32),digit(percent%10),"%"};len=4;tx=696;end
   end
   if(py>=314 && py<336 && px>=308)begin
    text=fx==0 ? "DELAY TIME" : fx==1 ? "ROOM MODEL" : "RATE";len=fx==2 ? 4 : 10;tx=308;ty=316;fg=DIM;
    if(px>=656 && fx==2)begin text={rate==10 ? 8'd49 : 8'd32,digit(rate%10)," HZ"};len=5;tx=688;fg=GOLD;end
   end
   if(fx!=2 && py>=344 && py<384 && px>=380)begin
    text=fx==0 ? "150 MS" : "SMALL ROOM";len=fx==0 ? 6 : 10;tx=fx==0 ? 510 : 490;ty=356;fg=CREAM;
   end
   if(ui_inside(px,py,664,420,116,44))begin
    base=card(px,py,664,420,116,44,1'b0);text="RESET";len=5;tx=697;ty=434;fg=GOLD;
   end
  end else begin
   if(ui_inside(px,py,20,128,552,196) || ui_inside(px,py,588,128,192,196) || ui_inside(px,py,20,338,760,68))base=PANEL;
   if(py>=94 && py<114)begin
    ty=96;fg=GOLD;
    if(px<296)begin text=timbre_name(timbre);len=name_length(timbre);tx=24;end
    else if(px<560)begin text=enabled ? (fx==0 ? "ECHO ON" : fx==1 ? "ROOM ON" : "TREMOLO ON") : "EFFECTS OFF";len=enabled ? (fx==2 ? 10 : 7) : 11;tx=310;end
    else begin text=state[14] ? "AUTO SCORE" : "LIVE KEYS";len=state[14] ? 10 : 9;tx=620;fg=DIM;end
   end
   if(ui_inside(px,py,32,164,512,140))begin
    if((px-32)%64==0 || (py-164)%35==0)base=24'h292c2c;
    bin=(px-32)>>2;
    point_y=234-($signed(state[88+bin*8+:8])>>>1);
    if(bin>0)previous_y=234-($signed(state[88+(bin-1)*8+:8])>>>1);else previous_y=point_y;
    minimum_y=point_y<previous_y ? point_y : previous_y;
    maximum_y=point_y>previous_y ? point_y : previous_y;
    if(py==point_y || ((px-32)%4==0 && py>=minimum_y && py<=maximum_y))base=GOLD;
   end
   if(py>=138 && py<158)begin
    ty=140;fg=DIM;
    if(px<390)begin text="OUTPUT WAVEFORM";len=15;tx=32;end
    else if(px<572)begin text="X1 DISPLAY";len=10;tx=440;end
    else begin text="LEVEL";len=5;tx=608;end
   end
   if(px>=608 && px<760 && py>=200 && py<224)base=(px-608)<(integer'(peak)*152>>8) ? (peak>=248 ? RED : GOLD) : BG;
   if(py>=244 && py<264 && px>=608)begin
    pc=(integer'(peak)*100+127)/255;
    text={pc==100 ? 8'd49 : 8'd32,pc>=10 ? digit((pc/10)%10) : 8'd32,digit(pc%10),"% PEAK"};len=9;tx=608;ty=246;fg=DIM;
   end
   if(py>=280 && py<300 && px>=608)begin text=peak>=248 ? "NEAR FULL" : "PCM OUTPUT";len=peak>=248 ? 9 : 10;tx=608;ty=282;fg=peak>=248 ? RED : DIM;end
   if(py>=348 && py<396 && px>=32 && px<768)begin
    note_index=(px-32)/46;left=32+note_index*46;
    if(px<left+42)begin
     base=state[64+note_index] ? GOLD : BG;fg=state[64+note_index] ? INK : DIM;
     // Exact chromatic MIDI60..75; these are monitors, not touch piano keys.
     case(note_index%12)
      0:ch="C";1:ch="C";2:ch="D";3:ch="D";4:ch="E";5:ch="F";
      6:ch="F";7:ch="G";8:ch="G";9:ch="A";10:ch="A";default:ch="B";
     endcase
     text={ch,(note_index%12==1 || note_index%12==3 || note_index%12==6 || note_index%12==8 || note_index%12==10) ? 8'd35 : 8'd32,digit(note_index<12 ? 4 : 5)};
     len=3;tx=left+6;ty=364;
    end
   end
  end
  // Shared header/status and mode action appear on both pages.
  if(py>=16 && py<64 && px>=648)begin
   text=menu ? "RETURN" : "SETTINGS";len=menu ? 6 : 8;tx=menu ? 684 : 674;ty=32;fg=GOLD;
  end
  if(px>=420 && px<640 && py>=22 && py<62)begin
   tx=430;fg=DIM;
   if(py<42)begin text={"VOICES ",digit(voices/10),digit(voices%10),"/32"};len=12;ty=24;end
   else begin text=state[15] ? "AUDIO READY" : "STARTING";len=state[15] ? 11 : 8;ty=46;fg=state[15] ? GREEN : GOLD;end
  end
  if(py>=420 && py<464 && px<648 && !(menu && px<336))begin
   tx=24;fg=DIM;
   if(py<440)begin
    text=menu ? "R4C2 PREV / R4C3 NEXT TIMBRE" : "S0 HOLD: SETTINGS";len=menu ? 28 : 17;ty=422;
    if(px>=336)begin
     if(!state[49])begin text="TOUCH OFF";len=9;end
     else if(state[52])begin text="TOUCH ERROR";len=11;fg=RED;end
     else if(!state[51])begin text="TOUCH WAIT";len=10;end
     else if(!state[50])begin text="TOUCH MONITOR";len=13;end
     else begin text="TOUCH READY";len=11;fg=GREEN;end
     tx=360;
    end
   end else begin
    text=menu ? "S1-/S2+ VOLUME" : "NOTE MONITOR C4-D#5 / 10.7 MS WINDOW";
    len=menu ? 14 : 36;ty=446;if(menu)tx=360;
    if(state[16] || state[17] || state[18])begin text=state[18] ? "GHOST KEYS" : "AUDIO ERROR";len=state[18] ? 10 : 11;fg=RED;end
   end
  end
  if(menu && ui_inside(px,py,24,420,292,44))begin
   fg=GOLD;ty=434;
   if(px<68 || px>=272)begin
    left=px<68 ? 24 : 272;base=card(px,py,left,420,44,44,0);
    text=px<68 ? "-" : "+";len=1;tx=left+17;
   end else begin
    text={"VOL ",volume==100 ? 8'd49 : 8'd32,volume>=10 ? digit((volume/10)%10) : 8'd32,digit(volume%10),"%"};len=8;tx=116;
   end
  end
  if(!menu && px>=620 && py>=440 && py<464)begin
   fg=DIM;tx=640;ty=446;len=13;
   if(state[1132])text={"LAT ",latency[19:16]!=0 ? digit(latency[19:16]) : 8'd32,
       latency[19:12]!=0 ? digit(latency[15:12]) : 8'd32,digit(latency[11:8]),".",
       digit(latency[7:4]),digit(latency[3:0])," MS"};
   else text="LAT ---.-- MS";
  end
  dx=$signed({1'b0,x})-$signed({1'b0,tx});dy=$signed({1'b0,y})-$signed({1'b0,ty});
  if(ui_inside(px,py,24,4,384,64))fg=GOLD;
  if(state[19])begin
   case(px/100)
    0:base=24'hffffff;1:base=24'hffff00;2:base=24'h00ffff;3:base=24'h00ff00;
    4:base=24'hff00ff;5:base=24'hff0000;6:base=24'h0000ff;default:base=0;
   endcase
   if(px==0 || px==799 || py==0 || py==479)base=CREAM;
  end
  if(!de_in || px>=800 || py>=480)begin base=0;end
 end
 // Synchronous font ROM; RGB/DE/HS/VS all traverse the same three stages.
 always @(posedge pixel_clk)begin
  font_row<=font_rom[font_addr];
  if(rst)begin glyph_text<=0;glyph_len<=0;glyph_dx<=0;glyph_dy<=0;glyph_title<=0;glyph_allow<=0;
   title_address<=0;title_bit<=0;base_layout<=0;fg_layout<=0;de_layout<=0;hs_layout<=0;vs_layout<=0;state<=0;base_pipe<=0;fg_pipe<=0;bit_pipe<=0;ink_pipe<=0;
   de_pipe<=0;hs_pipe<=0;vs_pipe<=0;rgb<=0;de_out<=0;hs_out<=0;vs_out<=0;end
  else begin
   if(frame_start && status_valid)state<=status_data;
   glyph_text<=text;glyph_len<=len;glyph_dx<=dx;glyph_dy<=dy;
   glyph_allow<=de_in && x<800 && y<480 && !state[19];
   glyph_title<=de_in && !state[19] && ui_inside(px,py,24,4,384,64);
   title_address<=1536+(py-4)*24+((px-24)>>4);title_bit<=15-((px-24)%16);
   base_layout<=base;fg_layout<=fg;de_layout<=de_in && x<800 && y<480;hs_layout<=hs_in;vs_layout<=vs_in;
   base_pipe<=base_layout;fg_pipe<=fg_layout;
   bit_pipe<=font_bit;ink_pipe<=text_ink;de_pipe<=de_layout;hs_pipe<=hs_layout;vs_pipe<=vs_layout;
   rgb<=ink_pipe && font_row[bit_pipe] ? fg_pipe : base_pipe;
   de_out<=de_pipe;hs_out<=hs_pipe;vs_out<=vs_pipe;
  end
 end
endmodule
