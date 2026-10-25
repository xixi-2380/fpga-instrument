`timescale 1ns/1ps
// Four visual themes. Nine registered pixel stages; RGB/DE/HS/VS aligned.
// One atomic1112-bit snapshot per frame; no framebuffer and no audio stalls.
module rgb_ui_renderer(
 input wire pixel_clk,rst,frame_start,status_valid,input wire [1111:0] status_data,
 input wire [10:0] x,y,input wire de_in,hs_in,vs_in,
 output reg [23:0] rgb,output reg de_out,hs_out,vs_out);
 reg [10:0] raster_x,raster_y;
 reg raster_de,raster_hs,raster_vs;
 always @(posedge pixel_clk)begin
  if(rst)begin raster_x<=0;raster_y<=0;raster_de<=0;raster_hs<=0;raster_vs<=0;end
  else begin raster_x<=x;raster_y<=y;raster_de<=de_in;raster_hs<=hs_in;raster_vs<=vs_in;end
 end
 `include "config/ui_layout.svh"
 // Palette changes are visual only; state bits 55:54 carry the theme.
 wire [1:0] theme=state[55:54];
 wire [1:0] font_theme=theme==3 ? 0 : theme;
 wire [23:0] BG=theme==0 ? 24'h101214 : theme==1 ? 24'hf7f1e8 : theme==2 ? 24'hfff1d9 : 24'he7e5e3;
 wire [23:0] PANEL=theme==0 ? 24'h191c20 : theme==1 ? 24'heee3d4 : theme==2 ? 24'hfbe3bc : 24'heee8e1;
 wire [23:0] GOLD=theme==0 ? 24'hd6b979 : theme==1 ? 24'h856b57 : theme==2 ? 24'ha3652c : 24'h884652;
 wire [23:0] CREAM=theme==0 ? 24'hf2e6c9 : theme==1 ? 24'h43392f : theme==2 ? 24'h493321 : 24'h332f2d;
 wire [23:0] INK=theme==0 ? 24'h17191b : 24'hfffaf1;
 wire [23:0] DIM=theme==0 ? 24'h9c987f : theme==1 ? 24'h73685c : 24'h7d6148;
 wire [23:0] LINE=theme==0 ? 24'h4b4534 : theme==1 ? 24'hcbbba7 : 24'hd9b889;
 wire [23:0] WINE=theme==0 ? 24'h67333e : 24'hb87e6c;
 wire [23:0] GREEN=theme==0 ? 24'h8bc79b : 24'h3d795f;
 localparam [23:0] RED=24'hef8f85;
 reg [1111:0] state;
 wire [2:0] timbre={state[53],state[13:12]};
 wire [1:0] fx=state[22:21];wire menu=state[20],enabled=state[23];
 wire [6:0] percent=fx==0 ? state[30:24] : fx==1 ? state[37:31] : state[44:38];
 wire [3:0] rate=state[48:45];
 wire [5:0] voices=state[5:0]>32 ? 6'd32 : state[5:0];
 wire [7:0] peak=state[87:80];
 reg [14:0] peak_scaled;
 reg [6:0] peak_percent;
 reg [7:0] peak_hundreds,peak_tens,peak_units,amount_hundreds,amount_tens,amount_units,voice_tens,voice_units;
 always @(posedge pixel_clk)begin
  if(rst)begin
   peak_scaled<=127;peak_percent<=0;
   peak_hundreds<=32;peak_tens<=32;peak_units<=48;
   amount_hundreds<=32;amount_tens<=32;amount_units<=48;voice_tens<=48;voice_units<=48;
  end else begin
   peak_scaled<=peak*15'd100+15'd127;peak_percent<=peak_scaled/15'd255;
   peak_hundreds<=peak_percent==100 ? 8'd49 : 8'd32;
   peak_tens<=peak_percent>=10 ? 8'd48+(peak_percent/7'd10)%7'd10 : 8'd32;
   peak_units<=8'd48+peak_percent%7'd10;
   amount_hundreds<=percent==100 ? 8'd49 : 8'd32;
   amount_tens<=percent>=10 ? 8'd48+(percent/7'd10)%7'd10 : 8'd32;
   amount_units<=8'd48+percent%7'd10;
   voice_tens<=8'd48+voices/6'd10;voice_units<=8'd48+voices%6'd10;
  end
 end
 reg [23:0] base,fg;
 reg [319:0] text;
 reg [5:0] len;reg [10:0] tx,ty;
 integer dx,dy,ci,px,py,i,k,left,top;reg [3:0] note_index;
 reg [6:0] bin; integer point_y,previous_y,minimum_y,maximum_y,pc;
 reg [7:0] ch;reg [13:0] font_addr;reg [3:0] font_bit;
 reg alpha_font;
 reg text_ink;
 reg [15:0] font_rom[0:16383],font_row;
 initial $readmemh("src/rom/theme_font.hex",font_rom);
 reg [25:0] animation_phase;
 reg [3:0] animation_frame;
 wire [23:0] art_pixel;
 ui_theme_art artwork(pixel_clk,theme,animation_frame,raster_x,raster_y,art_pixel,menu);
 // Limit color arithmetic to ten bits, rather than signed 32-bit division.
 function automatic [7:0] blend_channel(input [7:0] a,b,input [1:0] w);
  reg [9:0] sum;
  begin
   case(w)
    0:blend_channel=a;
    3:blend_channel=b;
    default:begin
     sum=w==1 ? ({2'b0,a}<<1)+{2'b0,b}+10'd1
              : {2'b0,a}+({2'b0,b}<<1)+10'd1;
     blend_channel=sum/10'd3;
    end
   endcase
  end
 endfunction
 function automatic [23:0] mix_color(input [23:0] a,b,input [1:0] weight);
  begin mix_color={blend_channel(a[23:16],b[23:16],weight),
   blend_channel(a[15:8],b[15:8],weight),blend_channel(a[7:0],b[7:0],weight)};end
 endfunction
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
 function [23:0] card(input integer xx,yy,l,t,w,h,input selected);
  begin
   card=selected ? (theme==0 ? CREAM : GOLD) : PANEL;
   if(xx<l+1 || xx>=l+w-1 || yy<t+1 || yy>=t+h-1)card=selected ? GOLD : LINE;
  end
 endfunction
 always @*begin
  px=integer'(raster_x);py=integer'(raster_y);base=BG;fg=CREAM;text=0;len=0;tx=0;ty=0;
  dx=0;dy=0;ci=0;i=0;k=0;left=0;top=0;note_index=0;pc=0;
  bin=0;point_y=234;previous_y=234;minimum_y=234;maximum_y=234;
  ch=0;font_addr=0;font_bit=0;text_ink=0;alpha_font=0;
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
    else begin text={amount_hundreds,amount_tens,amount_units,"%"};len=4;tx=696;end
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
  end else if(theme==3)begin
   // Easter performance page: a clear portrait at left, live monitors at
   // right. No waveform, card or held-note tile may cover the woman's face.
   if(ui_inside(px,py,464,128,316,124) || ui_inside(px,py,464,260,316,70) ||
      ui_inside(px,py,464,338,316,68))base=PANEL;
   if(py>=94 && py<114)begin
    ty=96;fg=GOLD;
    if(px<296)begin text=timbre_name(timbre);len=name_length(timbre);tx=24;end
    else if(px<560)begin text=enabled ? (fx==0 ? "ECHO ON" : fx==1 ? "ROOM ON" : "TREMOLO ON") : "EFFECTS OFF";len=enabled ? (fx==2 ? 10 : 7) : 11;tx=310;end
    else begin text=state[14] ? "AUTO SCORE" : "LIVE KEYS";len=state[14] ? 10 : 9;tx=620;fg=DIM;end
   end
   if(ui_inside(px,py,488,164,256,80))begin
    if((px-488)%32==0 || (py-164)%20==0)base=24'hd4d0cc;
    bin=(px-488)>>1;
    point_y=204-($signed(state[88+bin*8+:8])>>>2);
    previous_y=bin>0 ? 204-($signed(state[88+(bin-1)*8+:8])>>>2) : point_y;
    minimum_y=point_y<previous_y ? point_y : previous_y;
    maximum_y=point_y>previous_y ? point_y : previous_y;
    if(py==point_y || ((px-488)%2==0 && py>=minimum_y && py<=maximum_y))base=GOLD;
   end
   if(py>=138 && py<158 && px>=480)begin text="OUTPUT WAVEFORM";len=15;tx=488;ty=140;fg=DIM;end
   if(py>=268 && py<288 && px>=480)begin text="LEVEL";len=5;tx=488;ty=270;fg=DIM;end
   if(ui_inside(px,py,488,298,256,10))base=(px-488)<integer'(peak) ? GOLD : BG;
   if(py>=268 && py<288 && px>=640)begin
    pc=peak_percent;
    text={peak_hundreds,peak_tens,peak_units,"% PEAK"};len=9;tx=668;ty=270;fg=DIM;
   end
   if(ui_inside(px,py,480,342,288,60))begin
    note_index=py>=372 ? 8 : 0;left=480;top=py>=372 ? 372 : 342;
    for(integer tile=0;tile<8;tile=tile+1)
     if(px>=480+tile*36 && px<516+tile*36)begin note_index=note_index+tile;left=480+tile*36;end
    if(px<left+34 && py<top+28)begin
     base=state[64+note_index] ? GOLD : BG;fg=state[64+note_index] ? INK : DIM;
     case(note_index%12)
      0:ch="C";1:ch="C";2:ch="D";3:ch="D";4:ch="E";5:ch="F";
      6:ch="F";7:ch="G";8:ch="G";9:ch="A";10:ch="A";default:ch="B";
     endcase
     text={ch,(note_index%12==1 || note_index%12==3 || note_index%12==6 || note_index%12==8 || note_index%12==10) ? 8'd35 : 8'd32,digit(note_index<12 ? 4 : 5)};
     len=3;tx=left+2;ty=top+6;
    end
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
    else if(px<572)begin text="X8 DISPLAY";len=10;tx=440;end
    else begin text="LEVEL";len=5;tx=608;end
   end
   if(px>=608 && px<760 && py>=200 && py<224)base=(px-608)<(integer'(peak)*152>>8) ? (peak>=248 ? RED : GOLD) : BG;
   if(py>=244 && py<264 && px>=608)begin
    pc=peak_percent;
    text={peak_hundreds,peak_tens,peak_units,"% PEAK"};len=9;tx=608;ty=246;fg=DIM;
   end
   if(py>=280 && py<300 && px>=608)begin text=peak>=248 ? "NEAR FULL" : "PCM OUTPUT";len=peak>=248 ? 9 : 10;tx=608;ty=282;fg=peak>=248 ? RED : DIM;end
   if(py>=348 && py<396 && px>=32 && px<768)begin
    note_index=0;left=32;
    for(integer tile=0;tile<16;tile=tile+1)
     if(px>=32+tile*46 && px<78+tile*46)begin note_index=tile;left=32+tile*46;end
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
   if(py<42)begin text={"VOICES ",voice_tens,voice_units,"/32"};len=12;ty=24;end
   else begin text=state[15] ? "AUDIO READY" : "STARTING";len=state[15] ? 11 : 8;ty=46;fg=state[15] ? GREEN : GOLD;end
  end
  if(ui_inside(px,py,536,420,112,44))begin
   base=card(px,py,536,420,112,44,1'b0);text="THEME >";len=7;tx=557;ty=434;fg=GOLD;
  end
  if(py>=420 && py<464 && px<528)begin
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
    text=menu ? "R3: AMOUNT / RATE   R4C4: RETURN" : "NOTE MONITOR C4-D#5 / 10.7 MS WINDOW";
    len=menu ? 32 : 36;ty=446;
    if(state[16] || state[17] || state[18])begin text=state[18] ? "GHOST KEYS" : "AUDIO ERROR";len=state[18] ? 10 : 11;fg=RED;end
   end
  end
  // 2-bit antialiased whole-word script headings preserve joined strokes.
  if(theme==0 && menu)begin
   k=-1;left=308;top=98;
   if(ui_inside(px,py,32,98,200,24))begin k=0;left=32;end
   else if(ui_inside(px,py,308,98,200,24))k=1;
   else if(fx!=2 && ui_inside(px,py,308,204,200,24))begin k=2;top=204;end
   else if(fx==1 && ui_inside(px,py,308,310,200,24))begin k=3;top=310;end
   if(k>=0)begin
    font_addr=13824+k*600+(py-top)*25+((px-left)>>3);
    font_bit=14-((px-left)%8)*2;text_ink=1;alpha_font=1;fg=GOLD;
   end
  end
  if(ui_inside(px,py,24,4,384,64))begin
   font_addr=4608+integer'(font_theme)*3072+(py-4)*48+((px-24)>>3);
   font_bit=14-((px-24)%8)*2;text_ink=1;alpha_font=1;fg=GOLD;
  end
  if(state[19])begin
   case(1'b1)
    px<100:base=24'hffffff;px<200:base=24'hffff00;px<300:base=24'h00ffff;px<400:base=24'h00ff00;
    px<500:base=24'hff00ff;px<600:base=24'hff0000;px<700:base=24'h0000ff;default:base=0;
   endcase
   if(px==0 || px==799 || py==0 || py==479)base=CREAM;
   text_ink=0;
  end
  if(!raster_de || px>=800 || py>=480)begin base=0;text_ink=0;end
 end
 // S1 layout; S2 relative position; S3 cell; S4 character; S5 address;
 // S6 synchronous ROM; S7 background/alpha; S8 final text blend.
 localparam integer PIXEL_LATENCY=9;
 reg [319:0] text_s1,text_s2,text_s3;
 reg [5:0] len_s1,len_s2,len_s3;
 reg [10:0] x_s1,y_s1,tx_s1,ty_s1;
 reg signed [11:0] dx_s2,dy_s2;
 reg [5:0] cell_s3;
 reg [3:0] row_s3,normal_bit_s3,row_s4,normal_bit_s4,bit_s5,bit_s6;
 reg normal_ink_s3,normal_ink_s4,ink_s5,ink_s6;
 reg [7:0] char_s4;
 reg [13:0] addr_s5;
 reg [23:0] bases[0:5],foregrounds[0:5],arts[1:5];
 reg [13:0] direct_addr[0:3];reg [3:0] direct_bit[0:3];
 reg [3:0] direct_ink,direct_alpha;
 reg [1:0] fonts[0:3];
 reg [5:0] background,panels,blank,tests,des,hss,vss;
 reg [1:0] themes[0:5];
 reg [23:0] bg_s1,panel_s1;
 reg alpha_s5,alpha_s6;
 reg [23:0] resolved_s7,fg_s7;
 reg [1:0] alpha_s7;
 reg ink_s7,de_s7,hs_s7,vs_s7;
 // Unconditional synchronous ROM read preserves block-memory inference.
 always @(posedge pixel_clk)font_row<=font_rom[addr_s5];
 wire [5:0] glyph_index=len_s3-6'd1-cell_s3;
 wire normal_valid=dx_s2>=0 && dx_s2<({6'd0,len_s2}*12'd10) && dy_s2>=0 && dy_s2<16;
 always @(posedge pixel_clk)begin
  if(rst)begin
   state<=0;animation_phase<=0;animation_frame<=0;
   text_s1<=0;text_s2<=0;text_s3<=0;len_s1<=0;len_s2<=0;len_s3<=0;
   x_s1<=0;y_s1<=0;tx_s1<=0;ty_s1<=0;dx_s2<=0;dy_s2<=0;
   cell_s3<=0;row_s3<=0;normal_bit_s3<=0;normal_ink_s3<=0;
   char_s4<=0;row_s4<=0;normal_bit_s4<=0;normal_ink_s4<=0;
   addr_s5<=0;bit_s5<=0;ink_s5<=0;alpha_s5<=0;
   bit_s6<=0;ink_s6<=0;alpha_s6<=0;
   resolved_s7<=0;fg_s7<=0;alpha_s7<=0;ink_s7<=0;de_s7<=0;hs_s7<=0;vs_s7<=0;
   direct_ink<=0;direct_alpha<=0;background<=0;panels<=0;blank<=6'b111111;tests<=0;des<=0;hss<=0;vss<=0;
   for(integer q=0;q<6;q=q+1)begin bases[q]<=0;foregrounds[q]<=0;themes[q]<=0;end
   for(integer q=1;q<6;q=q+1)arts[q]<=0;
   for(integer q=0;q<4;q=q+1)begin direct_addr[q]<=0;direct_bit[q]<=0;fonts[q]<=0;end
   bg_s1<=0;panel_s1<=0;rgb<=0;de_out<=0;hs_out<=0;vs_out<=0;
  end else begin
   if(frame_start)begin
    if(status_valid)state<=status_data;
    if(status_valid && status_data[55:54]!=theme)begin animation_phase<=0;animation_frame<=0;end
    else if(theme==1 || theme==2)begin
     if(animation_phase>=26'd28646640)begin animation_phase<=animation_phase-26'd28646640;animation_frame<=animation_frame+1'b1;end
     else animation_phase<=animation_phase+26'd6353360;
    end
   end
   text_s1<=text;len_s1<=len;x_s1<=raster_x;y_s1<=raster_y;tx_s1<=tx;ty_s1<=ty;
   direct_addr[0]<=font_addr;direct_bit[0]<=font_bit;fonts[0]<=font_theme;
   direct_ink[0]<=text_ink;direct_alpha[0]<=alpha_font;
   bases[0]<=base;foregrounds[0]<=fg;themes[0]<=theme;
   bg_s1<=BG;panel_s1<=PANEL;background[0]<=0;panels[0]<=0;tests[0]<=state[19];
   blank[0]<=!raster_de || raster_x>=800 || raster_y>=480;des[0]<=raster_de && raster_x<800 && raster_y<480;hss[0]<=raster_hs;vss[0]<=raster_vs;
   for(integer q=1;q<6;q=q+1)begin
    bases[q]<=bases[q-1];foregrounds[q]<=foregrounds[q-1];themes[q]<=themes[q-1];
    if(q==1)begin background[q]<=bases[0]==bg_s1;panels[q]<=bases[0]==panel_s1;end
    else begin background[q]<=background[q-1];panels[q]<=panels[q-1];end
    tests[q]<=tests[q-1];blank[q]<=blank[q-1];
    des[q]<=des[q-1];hss[q]<=hss[q-1];vss[q]<=vss[q-1];
    if(q==1)arts[q]<=art_pixel;else arts[q]<=arts[q-1];
   end
   for(integer q=1;q<4;q=q+1)begin
    direct_addr[q]<=direct_addr[q-1];direct_bit[q]<=direct_bit[q-1];fonts[q]<=fonts[q-1];
    direct_ink[q]<=direct_ink[q-1];direct_alpha[q]<=direct_alpha[q-1];
   end
   // Positions are bounded to the 800x480 canvas, not 32-bit signed dividers.
   dx_s2<=$signed({1'b0,x_s1})-$signed({1'b0,tx_s1});
   dy_s2<=$signed({1'b0,y_s1})-$signed({1'b0,ty_s1});text_s2<=text_s1;len_s2<=len_s1;
   cell_s3<=normal_valid ? $unsigned(dx_s2)/12'd10 : 0;
   normal_bit_s3<=15-($unsigned(dx_s2)%12'd10);row_s3<=dy_s2[3:0];normal_ink_s3<=normal_valid;
   text_s3<=text_s2;len_s3<=len_s2;
   char_s4<=normal_ink_s3 ? text_s3[{glyph_index,3'b000}+:8] : 8'd32;
   row_s4<=row_s3;normal_bit_s4<=normal_bit_s3;normal_ink_s4<=normal_ink_s3;
   addr_s5<=direct_ink[3] ? direct_addr[3] : {fonts[3],10'd0}+({fonts[3],10'd0}>>1)+(char_s4-8'd32)*14'd16+row_s4;
   bit_s5<=direct_ink[3] ? direct_bit[3] : normal_bit_s4;
   ink_s5<=!blank[3] && !tests[3] && (direct_ink[3] || (normal_ink_s4 && char_s4>=32 && char_s4<128));
   alpha_s5<=direct_ink[3] && direct_alpha[3];
   bit_s6<=bit_s5;ink_s6<=ink_s5;alpha_s6<=alpha_s5;
   resolved_s7<=blank[5] ? 24'd0 : (!tests[5] && background[5]) ? arts[5] :
    (!tests[5] && panels[5] && themes[5]!=0) ? mix_color(bases[5],arts[5],2) : bases[5];
   fg_s7<=foregrounds[5];ink_s7<=ink_s6;
   alpha_s7<=alpha_s6 ? ((font_row>>bit_s6)&3) : (font_row[bit_s6] ? 3 : 0);
   de_s7<=des[5];hs_s7<=hss[5];vs_s7<=vss[5];
   rgb<=ink_s7 ? mix_color(resolved_s7,fg_s7,alpha_s7) : resolved_s7;
   de_out<=de_s7;hs_out<=hs_s7;vs_out<=vs_s7;
  end
 end
endmodule
