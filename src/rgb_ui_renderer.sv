`timescale 1ns/1ps
// British black/gold UI. Layout, coordinates, glyph/ROM and output: four stages.
// One atomic1208-bit snapshot per frame; no framebuffer and no audio stalls.
module rgb_ui_renderer #(parameter integer FRAME_LOCKED_INPUTS=0)(
 input wire pixel_clk,rst,frame_start,status_valid,input wire [1207:0] status_data,
 input wire [10:0] x,y,input wire de_in,hs_in,vs_in,
 output reg [23:0] rgb,output reg de_out,hs_out,vs_out,input wire [145:0] more_data,input wire [2591:0] pcb_data,output wire pcb_visible,input wire [63:0] performance_data);
 `include "config/ui_layout.svh"
 localparam [23:0] BG=24'h101214,PANEL=24'h191c20,GOLD=24'hd6b979,
  CREAM=24'hf2e6c9,INK=24'h17191b,DIM=24'h9c987f,LINE=24'h4b4534,
  WINE=24'h67333e,GREEN=24'h8bc79b,RED=24'hef8f85;
 wire [16:0] harp_neck_y=y*6'd48;wire [16:0] harp_neck_x=x*3'd7;
 reg [1207:0] state_q;reg [63:0] performance_state_q;
 // Frame-locked callers suppress de_in until status_valid; payload may be uninitialized.
 wire [1207:0] state=FRAME_LOCKED_INPUTS!=0 ? status_data : state_q;
 wire [63:0] performance_state=FRAME_LOCKED_INPUTS!=0 ? performance_data : performance_state_q;
 wire performance_page=performance_state[0]===1'b1 && !state[20];
 wire [2:0] effect_bits=state[1169:1167];
 wire echo_amount_edit=state[1170],tremolo_rate_edit=state[1171];
 wire [11:0] echo_ms_bcd=state[1183:1172];
 wire [35:0] piano_notes={state[1203:1184],state[79:64]};
 wire [2:0] keyboard_online=state[1206:1204];
 wire sensor_page=state[1166],sensor_enabled=state[1165];
 wire [2:0] sensor_sensitivity=state[1164:1162],sensor_state=state[1147:1145];
 wire [6:0] sensor_min=state[1161:1155],sensor_max=state[1154:1148];
 wire [11:0] sensor_distance=state[1144:1133];
 wire [19:0] latency=state[1131:1112];
 reg [145:0] more_state_q;reg [2591:0] pcb_state_q;
 wire [145:0] more_state=FRAME_LOCKED_INPUTS!=0 ? (more_data[81]===1'b1 ? more_data : 146'd0) : more_state_q;
 wire [2591:0] pcb_state=FRAME_LOCKED_INPUTS!=0 ? pcb_data : pcb_state_q;
 assign pcb_visible=pcb_state[2560];
 wire pcb_open=pcb_state[2560];wire [2:0] pcb_tab=pcb_state[2564:2562];
 wire pcb_frozen=pcb_state[2572],pcb_gsr=pcb_state[2573];
 wire [1:0] pcb_detail=pcb_state[2575:2574];
 wire [3:0] timbre={state[1207]===1'b1,state[53],state[13:12]};
 wire [1:0] fx=state[22:21];wire menu=state[20],enabled=state[23];
 wire [6:0] percent=fx==0 ? state[30:24] : fx==1 ? state[37:31] : state[44:38];
 wire [4:0] rate={state[61],state[48:45]};
 wire [15:0] sustain_ms_bcd={2'd0,state[63:62],echo_ms_bcd};
 wire [6:0] volume=state[60:54];
 wire [5:0] voices=state[5:0]>32 ? 6'd32 : state[5:0];
 wire [7:0] peak=state[87:80];
 reg [23:0] base,fg,base_pipe,fg_pipe;
 reg [319:0] text;
 reg [5:0] len,ci;
 reg [10:0] tx,ty;
 reg [319:0] layout_text;reg [5:0] layout_len;
 reg [10:0] layout_x,layout_y,layout_tx,layout_ty;
 reg layout_allow,layout_title;
 reg [11:0] layout_title_address;reg [3:0] layout_title_bit;
 reg [23:0] base_glyph,fg_glyph;
 reg de_glyph,hs_glyph,vs_glyph;
 integer px,py,i,k,left,top,note_index;reg [2:0] pcb_line;
 reg [6:0] bin;
 // Signed8 waveform samples map exactly to Y171..298; ten bits suffice.
 reg signed [9:0] point_y,previous_y,minimum_y,maximum_y;
 wire piano_row_hit=(y>=346 && y<362)||(y>=364 && y<380)||(y>=382 && y<398);
 wire [11:0] piano_row_notes=y<364 ? piano_notes[11:0] : y<382 ? piano_notes[23:12] : piano_notes[35:24];
 wire [11:0] piano_column_hit;
 for(genvar pcx=0;pcx<12;pcx=pcx+1)begin: piano_columns
  assign piano_column_hit[pcx]=x>=32+pcx*61 && x<91+pcx*61;
 end
 reg [3:0] piano_column;reg [10:0] piano_text_x;
 always @*begin
  piano_column=0;piano_text_x=38;
  for(integer c=0;c<12;c=c+1)if(piano_column_hit[c])begin piano_column=c;piano_text_x=38+c*61;end
 end
 wire piano_down=piano_row_notes[piano_column];
 reg [6:0] pc;
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
 // A valid glyph is inside <=40 ten-pixel cells: X is 0..399, never signed.
 // Bound the arithmetic before the variable character lookup.
 wire [16:0] glyph_tenths=glyph_dx[8:0]*8'd205;
 wire [5:0] glyph_cell=glyph_tenths[16:11];
 wire [3:0] glyph_column=glyph_dx[8:0]-glyph_cell*9'd10;
 wire [5:0] glyph_index=glyph_len-6'd1-glyph_cell;
 always @*begin
  font_addr=0;font_bit=0;text_ink=0;ci=0;glyph_char=0;
  if(glyph_allow && glyph_len>0 && glyph_dx>=0 && glyph_dx<glyph_len*12'd10 && glyph_dy>=0 && glyph_dy<16)begin
   ci=glyph_cell;glyph_char=glyph_text[{glyph_index,3'b000}+:8];
   if(glyph_char>=32 && glyph_char<128)begin font_addr={glyph_char-8'd32,4'b0000}+glyph_dy[3:0];font_bit=4'd15-glyph_column;text_ink=1;end
  end
  if(glyph_title)begin font_addr=title_address;font_bit=title_bit;text_ink=1;end
 end
 reg [15:0] font_rom[0:4095],font_row;
 initial $readmemh("src/rom/british_font.hex",font_rom);
 function automatic [7:0] digit(input integer value);
  begin digit=8'd48+value;end
 endfunction
 function automatic [7:0] hex_digit(input [3:0] value);
  begin hex_digit=value<10?8'd48+value:8'd65+value-8'd10;end
 endfunction
 function automatic [31:0] hex16(input [15:0] value);
  begin hex16={hex_digit(value[15:12]),hex_digit(value[11:8]),hex_digit(value[7:4]),hex_digit(value[3:0])};end
 endfunction
 function automatic [6:0] peak_percent(input [7:0] value);
  reg [15:0] numerator;reg [16:0] adjusted;
  begin
   numerator=value*16'd100+16'd127;
   // Exact /255 for 0..25627; avoids a signed 32-bit divider in the raster.
   adjusted={1'b0,numerator}+17'd1+(numerator>>8);
   peak_percent=adjusted[14:8];
  end
 endfunction
 function automatic [23:0] percent_text(input [6:0] value);
  begin percent_text={value==100 ? 8'd49 : 8'd32,value>=10 ? digit((value/10)%10) : 8'd32,digit(value%10)};end
 endfunction
 function automatic [79:0] timbre_name(input [3:0] id);
  begin case(id)
   1:timbre_name="FLUTE";2:timbre_name="REED";3:timbre_name="CELLO";
   4:timbre_name="PIANO";5:timbre_name="GUITAR";6:timbre_name="VIBRAPHONE";
   7:timbre_name="ORGAN";8:timbre_name="BASS";9:timbre_name="VIOLIN";10:timbre_name="STRINGS";11:timbre_name="TRUMPET";12:timbre_name="SAX";13:timbre_name="LEAD";14:timbre_name="PAD";15:timbre_name="ACCORDION";default:timbre_name="SINE";endcase end
 endfunction
 function automatic integer name_length(input [3:0] id);
  begin case(id)1,3,4:name_length=5;2,0:name_length=4;5:name_length=6;7:name_length=5;8,13:name_length=4;9:name_length=6;10,11:name_length=7;12,14:name_length=3;15:name_length=9;default:name_length=10;endcase end
 endfunction
 function automatic [23:0] card(input integer xx,yy,l,t,w,h,input selected);
  begin
   card=selected ? CREAM : PANEL;
   if(xx<l+1 || xx>=l+w-1 || yy<t+1 || yy>=t+h-1)card=selected ? GOLD : LINE;
  end
 endfunction
 always @*begin
  px=integer'(x);py=integer'(y);base=BG;fg=CREAM;text=0;len=0;tx=0;ty=0;
  i=0;k=0;left=0;top=0;note_index=0;pc=0;
  bin=0;point_y=234;previous_y=234;minimum_y=234;maximum_y=234;
  ch=0;pcb_line=0;
  // Sparse faint celestial motifs. Ornament is kept outside touch controls.
  if((py==78 && px>=20 && px<780) || (py==410 && px>=20 && px<780))base=LINE;
  if(px>398 && px<632 && py<72)begin
   if((px==412 && py>=6 && py<=14) || (py==10 && px>=408 && px<=416) ||
      (px==628 && py>=60 && py<=68) || (py==64 && px>=624 && px<=632))base=GOLD;
  end
  if(ui_inside(px,py,648,16,132,48))base=card(px,py,648,16,132,48,1'b0);
  if(menu && sensor_page)begin
   if(ui_inside(px,py,20,92,760,310))base=PANEL;
   if(py>=112 && py<132 && px<480)begin text="ULTRASONIC VOLUME";len=17;tx=40;ty=116;fg=GOLD;end
   if(ui_inside(px,py,500,100,248,52))begin
    base=card(px,py,500,100,248,52,sensor_enabled);fg=sensor_enabled ? INK : DIM;
    text=sensor_enabled ? "ON" : "OFF";len=sensor_enabled ? 2 : 3;tx=sensor_enabled ? 614 : 609;ty=118;
   end
   for(i=0;i<3;i=i+1)begin
    top=180+i*72;
    if(py>=top+12 && py<top+32 && px<480)begin
     text=i==0 ? "SENSITIVITY" : i==1 ? "MIN VOLUME" : "MAX VOLUME";
     len=i==0 ? 11 : 10;tx=40;ty=top+16;fg=GOLD;
    end
    if(ui_inside(px,py,500,top,64,48) || ui_inside(px,py,684,top,64,48))begin
     left=px<600 ? 500 : 684;base=card(px,py,left,top,64,48,0);
     text=px<600 ? "-" : "+";len=1;tx=left+27;ty=top+16;fg=GOLD;
    end
    if(px>=580 && px<676 && py>=top+12 && py<top+36)begin
     text=i==0 ? {digit(sensor_sensitivity)," / 5"} : {percent_text(i==1 ? sensor_min : sensor_max),"%"};
     len=i==0 ? 5 : 4;tx=i==0 ? 599 : 604;ty=top+16;fg=CREAM;
    end
   end
   if(py>=420 && py<442)begin
    tx=24;ty=424;fg=DIM;
    if(px<280)begin
     text=sensor_state==2 ? {"DIST ",digit(sensor_distance[11:8]),digit(sensor_distance[7:4]),".",digit(sensor_distance[3:0])," CM"} : "DIST --.- CM";len=12;
    end else if(px<490)begin text={"VOL ",percent_text(volume),"%"};len=8;tx=300;end
    else begin
     tx=520;
     case(sensor_state)
      0:begin text="OFF";len=3;end
      1:begin text="WAITING";len=7;end
      2:begin text="TRACKING";len=8;fg=GREEN;end
      3:begin text="HOLDING";len=7;fg=GOLD;end
      default:begin text="NO ECHO";len=7;fg=RED;end
     endcase
    end
   end
   if(py>=446 && py<464)begin text="CLOSER = LOUDER / S0 HOLD: HOME";len=31;tx=24;ty=446;fg=DIM;end
  end else if(menu)begin
   if(ui_inside(px,py,20,92,260,310) || ui_inside(px,py,296,92,484,88) ||
      ui_inside(px,py,296,194,484,102) || ui_inside(px,py,296,306,484,96))base=PANEL;
   for(i=0;i<8;i=i+1)begin
    left=timbre_x(i);top=timbre_y(i);
    if(ui_inside(px,py,left,top,112,52))begin
     base=card(px,py,left,top,112,52,timbre[2:0]==i);
     fg=timbre[2:0]==i ? INK : CREAM;text=timbre_name({timbre[3],3'(i)});len=name_length({timbre[3],3'(i)});
     tx=left+(112-name_length({timbre[3],3'(i)})*10)/2;ty=top+18;
    end
   end
   if(ui_inside(px,py,28,390,236,24))begin
    base=card(px,py,28,390,236,24,0);fg=GOLD;
    text=timbre[3]?"PAGE 2/2  NEXT":"PAGE 1/2  NEXT";len=14;tx=74;ty=394;
   end
   for(i=0;i<3;i=i+1)begin
    left=308+156*i;
    if(ui_inside(px,py,left,124,148,48))begin
     base=card(px,py,left,124,148,48,fx==i);fg=fx==i ? INK : CREAM;
     text=i==0 ? (effect_bits[0]?"SUST ON":"SUST OFF") :
          i==1 ? (effect_bits[1]?"ROOM ON":"ROOM OFF") : (effect_bits[2]?"TREM ON":"TREM OFF");
     len=effect_bits[i]?7:8;
     tx=left+(148-len*10)/2;ty=140;
    end
   end
   if(ui_inside(px,py,308,240,52,48) || ui_inside(px,py,716,240,52,48) ||
      (fx==2 && (ui_inside(px,py,308,344,52,48) || ui_inside(px,py,716,344,52,48))))begin
    left=px<400 ? 308 : 716;top=py<300 ? 240 : 344;
    base=card(px,py,left,top,52,48,1'b0);fg=GOLD;text=px<400 ? "-" : "+";len=1;tx=left+21;ty=top+16;
   end
   if(px>=380 && px<680 && py>=260 && py<270)base=(px-380)<integer'(percent)*3 ? GOLD : BG;
   if(fx==2 && px>=380 && px<680 && py>=366 && py<376)base=(px-380)<integer'(rate)*15 ? WINE : BG;
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
    text=fx==0 ? "TAIL TIME " : fx==1 ? "ROOM MODEL" : "RATE";len=fx==2 ? 4 : 10;tx=308;ty=316;fg=DIM;
    if(px>=656 && fx==2)begin text={rate>=10 ? digit(rate/10) : 8'd32,digit(rate%10)," HZ"};len=5;tx=688;fg=GOLD;end
   end
   if(fx!=2 && py>=344 && py<384 && px>=380)begin
    text=fx==0 ? {digit(sustain_ms_bcd[15:12]),digit(echo_ms_bcd[11:8]),digit(echo_ms_bcd[7:4]),digit(echo_ms_bcd[3:0])," MS"} : "SMALL ROOM";len=fx==0 ? 7 : 10;tx=fx==0 ? 510 : 490;ty=356;fg=CREAM;
   end
   if(px>=380 && py>=382 && py<402)begin
    text=fx==0 ? (echo_amount_edit ? "KNOB: AMOUNT" : "KNOB: TIME") :
         fx==1 ? "KNOB: AMOUNT" : (tremolo_rate_edit ? "KNOB: RATE" : "KNOB: DEPTH");
    len=fx==1 || (fx==0 && echo_amount_edit) ? 12 : fx==2 && !tremolo_rate_edit ? 11 : 10;
    tx=490;ty=384;fg=DIM;
   end
   if(ui_inside(px,py,664,420,116,44))begin
    base=card(px,py,664,420,116,44,1'b0);text="RESET";len=5;tx=697;ty=434;fg=GOLD;
   end
  end else begin
   if(ui_inside(px,py,20,128,552,196) || ui_inside(px,py,588,128,192,196) || ui_inside(px,py,20,338,760,68))base=PANEL;
   if(py>=94 && py<114)begin
    ty=96;fg=GOLD;
    if(px<296)begin text=timbre_name(timbre);len=name_length(timbre);tx=24;end
    else if(px<560)begin
     case(effect_bits)
      1:begin text="SUST ON";len=7;end
      2:begin text="ROOM ON";len=7;end
      3:begin text="SUST+ROOM";len=9;end
      4:begin text="TREMOLO ON";len=10;end
      5:begin text="SUST+TREM";len=9;end
      6:begin text="ROOM+TREM";len=9;end
      7:begin text="SUST+ROOM+TREM";len=14;end
      default:begin text="EFFECTS OFF";len=11;end
     endcase
     tx=310;
    end
    else begin text=state[14] ? "AUTO SCORE" : "LIVE KEYS";len=state[14] ? 10 : 9;tx=620;fg=DIM;end
   end
   if(ui_inside(px,py,32,164,512,140))begin
    if(x[5:0]==6'd32 || py==164 || py==199 || py==234 || py==269)base=24'h292c2c;
    bin=(px-32)>>2;
    point_y=234-($signed(state[88+bin*8+:8])>>>1);
    if(bin>0)previous_y=234-($signed(state[88+(bin-1)*8+:8])>>>1);else previous_y=point_y;
    minimum_y=point_y<previous_y ? point_y : previous_y;
    maximum_y=point_y>previous_y ? point_y : previous_y;
    if(py==point_y || (x[1:0]==0 && py>=minimum_y && py<=maximum_y))base=GOLD;
   end
   if(py>=138 && py<158)begin
    ty=140;fg=DIM;
    if(px<390)begin text="OUTPUT WAVEFORM";len=15;tx=32;end
    else if(px<572)begin text="X1 DISPLAY";len=10;tx=440;end
    else begin text="LEVEL";len=5;tx=608;end
   end
   if(px>=608 && px<760 && py>=200 && py<224)base=(px-608)<(integer'(peak)*152>>8) ? (peak>=248 ? RED : GOLD) : BG;
   if(py>=244 && py<264 && px>=608)begin
    pc=peak_percent(peak);
    text={pc==100 ? 8'd49 : 8'd32,pc>=10 ? digit((pc/10)%10) : 8'd32,digit(pc%10),"% PEAK"};len=9;tx=608;ty=246;fg=DIM;
   end
   if(py>=280 && py<300 && px>=608)begin text=peak>=248 ? "NEAR FULL" : "PCM OUTPUT";len=peak>=248 ? 9 : 10;tx=608;ty=282;fg=peak>=248 ? RED : DIM;end
   // Three chromatic octaves, matching the three PCB connector orders.
   // Decode a column and row once; avoid36 serial RGB priority muxes.
   if(piano_row_hit && (|piano_column_hit))begin
     base=piano_down ? GOLD : BG;fg=piano_down ? INK : DIM;
     case(piano_column)
      0,1:ch="C";2,3:ch="D";4:ch="E";5,6:ch="F";
      7,8:ch="G";9,10:ch="A";default:ch="B";
     endcase
     text={ch,(piano_column==1 || piano_column==3 || piano_column==6 || piano_column==8 || piano_column==10) ? 8'd35 : 8'd32,y<364 ? 8'd52 : y<382 ? 8'd53 : 8'd54};
     len=3;tx=piano_text_x;ty=y<364 ? 346 : y<382 ? 364 : 382;
   end
   if(py>=306 && py<324 && px<560)begin
    text={"PCB 1:",keyboard_online[0]?"ON ":"OFF"," 2:",keyboard_online[1]?"ON ":"OFF"," 3:",keyboard_online[2]?"ON ":"OFF"};
    len=21;tx=32;ty=306;fg=DIM;
   end
  end
  // Shared header/status and mode action appear on both pages.
  if(py>=16 && py<64 && px>=648)begin
   text=menu ? (sensor_page ? "BACK" : "RETURN") : "SETTINGS";
   len=menu ? (sensor_page ? 4 : 6) : 8;tx=menu ? (sensor_page ? 694 : 684) : 674;ty=32;fg=GOLD;
  end
  if(px>=420 && px<640 && py>=22 && py<62)begin
   tx=430;fg=DIM;
   if(py<42)begin text={"VOICES ",digit(voices/10),digit(voices%10),"/32"};len=12;ty=24;end
   else begin text=state[15] ? "AUDIO READY" : "STARTING";len=state[15] ? 11 : 8;ty=46;fg=state[15] ? GREEN : GOLD;end
  end
  if(py>=420 && py<464 && px<648 && !(menu && px<336) && !(menu && sensor_page))begin
   tx=24;fg=DIM;
   if(py<440)begin
    text=menu ? "TOUCH TO ADJUST" : "S0 HOLD: SETTINGS";len=menu ? 15 : 17;ty=422;
    if(px>=336)begin
     if(!state[49])begin text="TOUCH OFF";len=9;end
     else if(state[52])begin text="TOUCH ERROR";len=11;fg=RED;end
     else if(!state[51])begin text="TOUCH WAIT";len=10;end
     else if(!state[50])begin text="TOUCH MONITOR";len=13;end
     else begin text="TOUCH READY";len=11;fg=GREEN;end
     tx=360;
    end
   end else begin
    text=menu ? "S1-/S2+ VOLUME" : "NOTE MONITOR C4-B6 / 10.7 MS WINDOW";
    len=menu ? 14 : 35;ty=446;if(menu)tx=360;
    if(state[16] || state[17] || state[18])begin text=state[18] ? "GHOST KEYS" : "AUDIO ERROR";len=state[18] ? 10 : 11;fg=RED;end
   end
  end
  if(menu && !sensor_page && ui_inside(px,py,24,420,292,44))begin
   fg=GOLD;ty=434;
   if(px<68 || px>=272)begin
    left=px<68 ? 24 : 272;base=card(px,py,left,420,44,44,0);
    text=px<68 ? "-" : "+";len=1;tx=left+17;if(sensor_enabled)fg=LINE;
   end else begin
    text={"VOL ",volume==100 ? 8'd49 : 8'd32,volume>=10 ? digit((volume/10)%10) : 8'd32,digit(volume%10),"%"};len=8;tx=116;
   end
  end
  if(menu && !sensor_page && ui_inside(px,py,550,420,104,44))begin
   base=card(px,py,550,420,104,44,0);fg=GOLD;text="more";len=4;tx=582;ty=434;
  end
  // Minimal fixed character rows; original two pages retain their layout.
  if(menu && more_state[81])begin
   base=BG;fg=CREAM;text=0;len=0;tx=24;ty=32;
   if(py<80)begin
    if(px<648)begin text="MORE";len=4;end else begin text="BACK";len=4;tx=680;fg=GOLD;end
   end else if(py<124)begin text=more_state[79]?"ID CHECK 02 / SRC RX HOLD":"BT  16 VOICES / 4096 NOTES";len=more_state[79]?25:26;ty=100;end
   else if(py<180)begin
    text={"SONG S",digit((integer'(more_state[4:0])+1)/100),digit(((integer'(more_state[4:0])+1)/10)%10),digit((integer'(more_state[4:0])+1)%10),more_state[5]?" VALID":" EMPTY"};len=15;ty=148;
   end else if(py>=200 && py<240)begin
    i=px<204?0:px<384?1:px<564?2:3;tx=24+i*180;ty=212;
    case(i)0:begin text="PREV";len=4;end 1:begin text="NEXT";len=4;end 2:begin text="LOAD";len=4;end default:begin text="PLAY";len=4;end endcase
   end else if(py>=252 && py<292)begin
    i=px<204?0:px<384?1:2;tx=24+i*180;ty=264;
    case(i)0:begin text="PAUSE";len=5;end 1:begin text="RESUME";len=6;end default:begin text="STOP";len=4;end endcase
   end else if(py>=304 && py<344)begin
    i=px<204?0:px<384?1:2;tx=24+i*180;ty=316;fg=GOLD;
    case(i)0:begin text="SAVE";len=4;end 1:begin text="DELETE";len=6;end default:begin text="FLASH INFO";len=10;end endcase
   end else if(py>=356 && py<388)begin
    text={more_state[6]?"BUSY ":"READY"," ID ",hex_digit(more_state[57:54]),hex_digit(more_state[53:50]),hex_digit(more_state[49:46]),hex_digit(more_state[45:42]),hex_digit(more_state[41:38]),hex_digit(more_state[37:34])};len=15;ty=364;
    if(!more_state[58])begin text="FLASH UNKNOWN / READ ONLY";len=25;fg=GOLD;end
    if(more_state[79])begin
     text={"ID ",hex_digit(more_state[57:54]),hex_digit(more_state[53:50]),hex_digit(more_state[49:46]),hex_digit(more_state[45:42]),hex_digit(more_state[41:38]),hex_digit(more_state[37:34])," JOB ",hex_digit(more_state[76:73]),hex_digit(more_state[72:69]),hex_digit(more_state[68:65]),hex_digit(more_state[64:61])};len=18;fg=GOLD;
    end
   end else if(py>=400 && py<428)begin
    text={"ERROR ",hex_digit(more_state[15:12]),hex_digit(more_state[11:8]),"   ",more_state[17:16]==1?"PLAYING":more_state[17:16]==2?"PAUSED ":"STOPPED"};len=18;ty=406;fg=more_state[15:8]!=0?RED:DIM;
    if(more_state[79])begin
     text={"SRC ",hex16(more_state[97:82])," RX ",hex16(more_state[113:98])," H ",hex16(more_state[145:130]),hex16(more_state[129:114])};len=27;fg=GOLD;
    end
   end else if(py>=436 && py<468)begin
    text=more_state[80]?"DELETE AGAIN TO CONFIRM / BACK CANCEL":"TOUCH BACK / S0 HOLD EXIT";len=more_state[80]?37:25;ty=442;fg=GOLD;
   end
  end
  if(menu && !sensor_page && !more_state[81] && ui_inside(px,py,340,420,96,44))begin
   base=card(px,py,340,420,96,44,sensor_enabled);fg=sensor_enabled ? INK : GOLD;
   text="ULTRA";len=5;tx=364;ty=434;
  end
  if(menu && !sensor_page && !more_state[81] && ui_inside(px,py,444,420,96,44))begin
   base=card(px,py,444,420,96,44,0);fg=GOLD;text="PCB";len=3;tx=476;ty=434;
  end
  if(!menu && px>=620 && py>=440 && py<464)begin
   fg=DIM;tx=640;ty=446;len=13;
   if(state[1132])text={"LAT ",latency[19:16]!=0 ? digit(latency[19:16]) : 8'd32,
       latency[19:12]!=0 ? digit(latency[15:12]) : 8'd32,digit(latency[11:8]),".",
       digit(latency[7:4]),digit(latency[3:0])," MS"};
   else text="LAT ---.-- MS";
  end
  if(ui_inside(px,py,24,4,384,64))fg=GOLD;
  if(state[19])begin
   if(px<100)base=24'hffffff;else if(px<200)base=24'hffff00;
   else if(px<300)base=24'h00ffff;else if(px<400)base=24'h00ff00;
   else if(px<500)base=24'hff00ff;else if(px<600)base=24'hff0000;
   else if(px<700)base=24'h0000ff;else base=24'h000000;
   if(px==0 || px==799 || py==0 || py==479)base=CREAM;
  end
  if(pcb_open)begin
   base=BG;fg=CREAM;text=0;len=0;tx=24;ty=32;
   if(py<72)begin
    if(px<648)begin
     text="KEYBOARD SETUP / MUTED";len=22;fg=GOLD;
     if(px>=400)begin text={"BUILD ",hex16(PCB_BUILD_ID[31:16]),hex16(PCB_BUILD_ID[15:0])};len=14;tx=430;end
    end
    else begin if(ui_inside(px,py,648,16,132,48))base=card(px,py,648,16,132,48,0);text="BACK";len=4;tx=690;fg=GOLD;end
   end else if(py>=80 && py<120)begin
    i=px<176?0:px<328?1:px<480?2:px<632?3:4;
    left=24+i*152;tx=left+12;ty=92;len=8;
    if(ui_inside(px,py,left,80,144,40))base=card(px,py,left,80,144,40,pcb_tab==i);fg=pcb_tab==i?INK:GOLD;
    case(i)0:text="OVERVIEW";1:begin text="SENSITIVITY";len=11;end 2:text="I2C LINK";3:text="KEY TEST";default:text="KNOBS   ";endcase
   end else if(py>=134 && py<178)begin
    ty=148;fg=GOLD;
    if(px<244)begin left=px<132?24:132;text=px<132?"PCB -":"PCB +";len=5;end
    else if(px<464)begin left=px<352?244:352;text=px<352?"CH -":"CH +";len=4;end
    else if(px<576)begin left=464;text=pcb_gsr?"EDIT GSR":"EDIT KOR";len=8;end
    else if(px<688)begin left=576;text={"MORE ",hex_digit({2'd0,pcb_detail})};len=6;end
    else begin left=688;text=pcb_frozen?"LIVE":"FREEZE";len=pcb_frozen?4:6;end
    tx=left+12;if(ui_inside(px,py,left,134,left==688?88:100,44))base=card(px,py,left,134,left==688?88:100,44,pcb_frozen && left==688);
   end else if(py>=196 && py<388)begin
    if(py<220)begin pcb_line=3'd0;ty=196;end else if(py<244)begin pcb_line=3'd1;ty=220;end
    else if(py<268)begin pcb_line=3'd2;ty=244;end else if(py<292)begin pcb_line=3'd3;ty=268;end
    else if(py<316)begin pcb_line=3'd4;ty=292;end else if(py<340)begin pcb_line=3'd5;ty=316;end
    else if(py<364)begin pcb_line=3'd6;ty=340;end else begin pcb_line=3'd7;ty=364;end
    case(pcb_line)
     3'd0:text=pcb_state[0+:320];
     3'd1:text=pcb_state[320+:320];
     3'd2:text=pcb_state[640+:320];
     3'd3:text=pcb_state[960+:320];
     3'd4:text=pcb_state[1280+:320];
     3'd5:text=pcb_state[1600+:320];
     3'd6:text=pcb_state[1920+:320];
     3'd7:text=pcb_state[2240+:320];
    endcase;len=40;tx=32;fg=pcb_line==0?GOLD:CREAM;
   end else if(py>=420 && py<464)begin
    ty=434;fg=GOLD;
    if(px<150)begin left=24;text="APPLY";len=5;end
    else if(px<276)begin left=150;text="DEFAULT";len=7;end
    else if(px<402)begin left=276;text="REINIT";len=6;end
    else if(px<528)begin left=402;text="ALL KOR";len=7;end
    else if(px<654)begin left=528;text="CLEAR";len=5;end
    else if(px<720)begin left=654;text="-";len=1;end
    else begin left=720;text="+";len=1;end
    tx=left+12;if(ui_inside(px,py,left,420,left>=654?56:116,44))base=card(px,py,left,420,left>=654?56:116,44,0);
    if(pcb_state[2571] && left<528)fg=LINE;
   end
  end
  if(!menu && !performance_page && ui_inside(px,py,456,16,176,48))begin
   base=card(px,py,456,16,176,48,0);fg=GOLD;text="HARP / FX";len=9;tx=496;ty=32;
  end
  if(performance_page)begin
   base=24'h182b2a;fg=24'hf4e3bb;text=0;len=0;tx=24;ty=32;
   // Jade, aged walnut and brass; fixed geometry with no external image RAM.
   if(py<80 || py>=416)base=24'h122320;
   if((py==78 || py==414) && px>=20 && px<780)base=24'h8d7952;
   if(px<688 && py>=92 && py<376)begin
    if((px[6:0]==32 || px[6:0]==96) && py[5:0]==16)base=24'h25413b;
    if((px>=64 && px<88 && py>=110 && py<352) ||
       (px>=664 && px<684 && py>=198 && py<352) ||
       (px>=64 && px<684 && py>=338 && py<354))begin
     base=px[2:0]==0?24'hbc985b:24'h684735;
    end
    if(px>=76 && px<684 && harp_neck_y>=harp_neck_x+17'd4700 && harp_neck_y<harp_neck_x+17'd5360)base=24'h795338;
    for(i=0;i<12;i=i+1)begin
     left=112+i*48;top=132+i*7;
     
     if(px>=left-3 && px<=left+3 && py>=top-10 && py<top-4)base=24'hc5a46c;
     if(px>=left-1 && px<=left+1 && py>=top && py<338)
      base=performance_state[9+i]?24'hfff5bf:24'hc8b88b;
     if(performance_state[9+i] && px>=left-4 && px<=left+4 && py>=top && py<338 && px!=left)
      base=24'h8b9361;
     if(py>=356 && py<372 && px>=left-10 && px<left+18)begin
      tx=left-10;ty=356;len=2;fg=24'hd9c79e;
      case(i%5)0:text="C ";1:text="D ";2:text="E ";3:text="G ";default:text="A ";endcase
     end
    end
   end
   if(py<72 && px>=456 && px<632)begin text="KONGHOU";len=7;tx=484;ty=32;fg=GOLD;end
   if(ui_inside(px,py,648,16,136,48))begin base=card(px,py,648,16,136,48,0);text="BACK";len=4;tx=696;ty=32;fg=GOLD;end
   if(px>=696 && py>=92 && py<368)begin
    if(py<164)begin top=104;text=performance_state[1]?"ON":"OFF";len=performance_state[1]?2:3;end
    else if(py<232)begin top=176;text={percent_text(performance_state[4:2]==1?7'd13:performance_state[4:2]==2?7'd25:performance_state[4:2]==3?7'd38:7'd50),"%"};len=4;end
    else if(py<300)begin top=244;text=performance_state[6:5]==0?"LOW":performance_state[6:5]==1?"MID":"HIGH";len=performance_state[6:5]==2?4:3;end
    else begin top=312;text=performance_state[8:7]==0?"SLOW":performance_state[8:7]==1?"MID":"FAST";len=performance_state[8:7]==1?3:4;end
    tx=712;ty=top+18;fg=GOLD;
    if(ui_inside(px,py,704,top,80,48))base=card(px,py,704,top,80,48,0);
   end
   if(px>=700 && py>=160 && py<176)begin text="MIX";len=3;tx=712;ty=160;fg=DIM;end
   if(px>=700 && py>=228 && py<244)begin text="DEPTH";len=5;tx=704;ty=228;fg=DIM;end
   if(px>=700 && py>=296 && py<312)begin text="RATE";len=4;tx=712;ty=296;fg=DIM;end
   if(px>=692 && py>=82 && py<98)begin text="CHORUS";len=6;tx=704;ty=84;fg=GOLD;end
   if(ui_inside(px,py,128,380,544,24))begin
    base=24'h40534a;
    if(px>=398 && px<=402)base=24'h8d7952;
    if(px>=140+performance_state[30:21] && px<=148+performance_state[30:21])base=24'he4ca8a;
   end
   if(py>=420 && py<468)begin
    if(ui_inside(px,py,24,420,140,48))begin base=card(px,py,24,420,140,48,0);text=performance_state[33]?timbre_name(timbre):"GUITAR";len=performance_state[33]?name_length(timbre):6;tx=36;ty=436;end
    else if(ui_inside(px,py,184,420,140,48))begin base=card(px,py,184,420,140,48,0);text="STOP / BACK";len=11;tx=198;ty=436;end
    else if(px>=344)begin
     text=performance_state[32]?"BT PLAYING / HARP PAUSED":!performance_state[31]?"TOUCH WAIT / RELEASE TO ARM":"BEND +/-2 SEMITONES / RELEASE=CENTER";
     len=performance_state[32]?24:!performance_state[31]?27:36;tx=344;ty=436;fg=DIM;
    end
   end
  end
  if(!de_in || px>=800 || py>=480)begin base=0;end
 end
 // Synchronous font ROM; RGB/DE/HS/VS traverse the same four stages.
 always @(posedge pixel_clk)begin
  font_row<=font_rom[font_addr];
  if(rst)begin
   layout_text<=0;layout_len<=0;layout_x<=0;layout_y<=0;layout_tx<=0;layout_ty<=0;
   layout_allow<=0;layout_title<=0;layout_title_address<=0;layout_title_bit<=0;
   base_glyph<=0;fg_glyph<=0;de_glyph<=0;hs_glyph<=0;vs_glyph<=0;
   glyph_text<=0;glyph_len<=0;glyph_dx<=0;glyph_dy<=0;glyph_title<=0;glyph_allow<=0;
   title_address<=0;title_bit<=0;base_layout<=0;fg_layout<=0;de_layout<=0;hs_layout<=0;vs_layout<=0;state_q<=0;base_pipe<=0;fg_pipe<=0;bit_pipe<=0;ink_pipe<=0;
   de_pipe<=0;hs_pipe<=0;vs_pipe<=0;rgb<=0;de_out<=0;hs_out<=0;vs_out<=0;more_state_q<=0;pcb_state_q<=0;performance_state_q<=0;end
  else begin
   if(FRAME_LOCKED_INPUTS==0 && frame_start && status_valid)begin performance_state_q<=performance_data;state_q<=status_data;more_state_q<=more_data[81]===1'b1 ? more_data : 146'd0;pcb_state_q<={pcb_data[2591:2561],pcb_data[2560]===1'b1,pcb_data[2559:0]};end
   layout_text<=text;layout_len<=len;layout_x<=x;layout_y<=y;layout_tx<=tx;layout_ty<=ty;
   glyph_text<=layout_text;glyph_len<=layout_len;
   glyph_dx<=$signed({1'b0,layout_x})-$signed({1'b0,layout_tx});
   glyph_dy<=$signed({1'b0,layout_y})-$signed({1'b0,layout_ty});
   layout_allow<=de_in && x<800 && y<480 && !state[19];
   layout_title<=de_in && !state[19] && !(menu && more_state[81]) && !pcb_open && ui_inside(px,py,24,4,384,64);
   layout_title_address<=1536+(py-4)*24+((px-24)>>4);layout_title_bit<=15-((px-24)%16);
   base_layout<=base;fg_layout<=fg;de_layout<=de_in && x<800 && y<480;hs_layout<=hs_in;vs_layout<=vs_in;
   glyph_allow<=layout_allow;glyph_title<=layout_title;
   title_address<=layout_title_address;title_bit<=layout_title_bit;
   base_glyph<=base_layout;fg_glyph<=fg_layout;de_glyph<=de_layout;hs_glyph<=hs_layout;vs_glyph<=vs_layout;
   base_pipe<=base_glyph;fg_pipe<=fg_glyph;
   bit_pipe<=font_bit;ink_pipe<=text_ink;de_pipe<=de_glyph;hs_pipe<=hs_glyph;vs_pipe<=vs_glyph;
   rgb<=ink_pipe && font_row[bit_pipe] ? fg_pipe : base_pipe;
   de_out<=de_pipe;hs_out<=hs_pipe;vs_out<=vs_pipe;
  end
 end
endmodule
