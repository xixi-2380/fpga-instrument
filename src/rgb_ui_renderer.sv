`timescale 1ns/1ps
// One shared 5x7 glyph lookup, two pixel registers. No framebuffer or CPU.
// Audio-domain settings are atomically transferred, then latched per frame.
module rgb_ui_renderer(
 input wire pixel_clk,rst,frame_start,status_valid,input wire [63:0] status_data,
 input wire [10:0] x,y,input wire de_in,hs_in,vs_in,
 output reg [23:0] rgb,output reg de_out,hs_out,vs_out);
 `include "config/ui_layout.svh"
 localparam [23:0] BG=24'h0b1220,PANEL=24'h152235,BUTTON=24'h1c2d44,
  SELECTED=24'h213e4b,WHITE=24'hedf4ff,DIM=24'h91a5bd,CYAN=24'h41d9cf,
  GREEN=24'h83e6b1,AMBER=24'hffbf69,RED=24'hff6b7a;
 reg [63:0] state;
 wire [1:0] timbre=state[13:12],fx=state[22:21];
 wire menu=state[20],enabled=state[23];
 wire [6:0] amount_percent=fx==0?state[30:24]:fx==1?state[37:31]:state[44:38];
 wire [3:0] rate=state[48:45];
 wire [5:0] voices=state[5:0]>32?6'd32:state[5:0];
 wire [4:0] amount_ticks=amount_percent/7'd5;
 reg [23:0] base,text_color;
 reg [287:0] text;
 integer length,tx,ty,scale,dx,dy,char_index,col,row;
 reg [7:0] character;
 reg ink;
 reg [5:0] bit_index;
 reg [23:0] base_pipe,text_pipe;
 reg [7:0] char_pipe;
 reg [5:0] bit_pipe;
 reg ink_pipe,de_pipe,hs_pipe,vs_pipe;
 wire [34:0] glyph_bits=glyph(char_pipe);
 function automatic [7:0] digit(input integer value);
  begin digit=8'd48+value;end
 endfunction
 function automatic [23:0] button_color(input integer px,py,left,top,width,height,
  input chosen,input [23:0] accent);
  begin
   button_color=chosen?SELECTED:BUTTON;
   if(px<left+2 || px>=left+width-2 || py<top+2 || py>=top+height-2)
    button_color=chosen?accent:24'h30455e;
  end
 endfunction
    function automatic [34:0] glyph(input [7:0] ch);
        begin
            case(ch)
                "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
                "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
                "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
                "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
                "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
                "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
                "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
                "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
                "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
                "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
                "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                "/":glyph=35'b00001_00001_00010_00100_01000_10000_10000;
                "?":glyph=35'b01110_10001_00001_00010_00100_00000_00100;
                "J":glyph=35'b00111_00010_00010_00010_10010_10010_01100;
                "Q":glyph=35'b01110_10001_10001_10001_10101_10010_01101;
                "Z":glyph=35'b11111_00001_00010_00100_01000_10000_11111;
                "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
                "+":glyph=35'b00000_00100_00100_11111_00100_00100_00000;
                "%":glyph=35'b11001_11010_00100_01000_10110_00110_00000;
                ":":glyph=35'b00000_00100_00100_00000_00100_00100_00000;
                default:glyph=0;
            endcase
        end
    endfunction

 always @*begin
  base=BG;text_color=WHITE;text=0;length=0;tx=0;ty=0;scale=2;
  character=0;ink=0;bit_index=0;dx=0;dy=0;char_index=0;col=0;row=0;
  if(ui_inside(x,y,24,288,368,104) || ui_inside(x,y,408,288,368,104))base=PANEL;
  if(ui_inside(x,y,624,16,152,56))base=button_color(x,y,624,16,152,56,menu,CYAN);
  if(ui_inside(x,y,24,104,176,60))base=button_color(x,y,24,104,176,60,timbre==0,CYAN);
  if(ui_inside(x,y,216,104,176,60))base=button_color(x,y,216,104,176,60,timbre==1,CYAN);
  if(ui_inside(x,y,408,104,176,60))base=button_color(x,y,408,104,176,60,timbre==2,CYAN);
  if(ui_inside(x,y,608,104,168,60))base=button_color(x,y,608,104,168,60,enabled,GREEN);
  if(ui_inside(x,y,24,208,240,60))base=button_color(x,y,24,208,240,60,fx==0,GREEN);
  if(ui_inside(x,y,280,208,240,60))base=button_color(x,y,280,208,240,60,fx==1,GREEN);
  if(ui_inside(x,y,536,208,240,60))base=button_color(x,y,536,208,240,60,fx==2,GREEN);
  if(ui_inside(x,y,40,328,64,56) || ui_inside(x,y,312,328,64,56))base=BUTTON;
  if(fx==2 && (ui_inside(x,y,424,328,64,56) || ui_inside(x,y,696,328,64,56)))base=BUTTON;
  if(ui_inside(x,y,624,408,152,56))base=button_color(x,y,624,408,152,56,1'b0,DIM);
  if(x>=128 && x<288 && y>=350 && y<362)
   base=((x-11'd128)>>3)<amount_ticks && x[2:0]!=7?CYAN:BG;
  if(fx==2 && x>=512 && x<672 && y>=350 && y<362)
   base=((x-11'd512)>>4)<rate && x[3:0]<14?GREEN:BG;
  // Mutually exclusive text bands feed a single character mux and glyph ROM.
  if(y>=16 && y<72)begin
   if(x>=624)begin text=menu?"PLAY":"MENU";length=4;tx=664;ty=34;scale=3;text_color=menu?CYAN:WHITE;end
   else if(y<46)begin text="FPGA INSTRUMENT";length=15;tx=24;ty=18;scale=3;end
   else begin text=menu?"PARAMETER CONTROL":"LIVE PERFORMANCE";length=menu?17:16;tx=24;ty=50;text_color=DIM;end
  end else if(y>=80 && y<98)begin text="TIMBRE";length=6;tx=24;ty=80;text_color=DIM;
  end else if(y>=104 && y<164)begin
   ty=123;scale=3;
   if(x<208)begin text="SINE";length=4;tx=76;end
   else if(x<400)begin text="FLUTE";length=5;tx=259;end
   else if(x<600)begin text="REED";length=4;tx=460;end
   else begin text=enabled?"FX ON":"FX OFF";length=enabled?5:6;tx=enabled?647:638;text_color=enabled?GREEN:AMBER;end
  end else if(y>=184 && y<202)begin text="EFFECT";length=6;tx=24;ty=184;text_color=DIM;
  end else if(y>=208 && y<268)begin
   ty=227;scale=3;
   if(x<272)begin text="ECHO";length=4;tx=108;end
   else if(x<528)begin text="ROOM";length=4;tx=364;end
   else begin text="TREMOLO";length=7;tx=593;end
  end else if(y>=296 && y<316)begin
   ty=296;text_color=DIM;
   if(x<280)begin text=fx==2?"DEPTH":"AMOUNT";length=fx==2?5:6;tx=40;end
   else if(x<400)begin text={(amount_percent>=100?8'd49:8'd32),(amount_percent>=10?digit((amount_percent/10)%10):8'd32),digit(amount_percent%10),"%"};length=4;tx=312;text_color=CYAN;end
   else if(x<680)begin text=fx==0?"DELAY TIME":fx==1?"ROOM MODEL":"RATE";length=fx==2?4:10;tx=424;end
   else if(fx==2)begin text={(rate>=10?8'd49:8'd32),digit(rate%10),"HZ"};length=4;tx=704;text_color=GREEN;end
  end else if(y>=328 && y<384)begin
   ty=345;scale=3;
   if(x<112)begin text="-";length=1;tx=64;end
   else if(x>=312 && x<392)begin text="+";length=1;tx=336;end
   else if(x>=408)begin
    if(fx!=2)begin text=fx==0?"150 MS":"SMALL ROOM";length=fx==0?6:10;tx=fx==0?538:502;text_color=DIM;end
    else if(x<496)begin text="-";length=1;tx=448;end
    else if(x>=696)begin text="+";length=1;tx=720;end
   end
  end else if(y>=408 && y<476)begin
   if(x>=624)begin text="RESET";length=5;tx=655;ty=426;scale=3;end
   else if(y<426)begin
    ty=408;
    if(x<192)begin text={"VOICES ",digit(voices/10),digit(voices%10),"/32"};length=12;tx=24;end
    else if(x<320)begin text=state[15]?"READY":"STARTING";length=state[15]?5:8;tx=196;text_color=state[15]?GREEN:AMBER;end
    else if(x<432)begin text=state[14]?"DEMO":"LIVE";length=4;tx=328;text_color=CYAN;end
    else if(state[16] || state[17] || state[18])begin text=state[18]?"GHOST":"ERROR";length=5;tx=448;text_color=RED;end
   end else if(y<450)begin
    ty=432;
    if(x<208)begin
     if(!state[49])begin text="TOUCH OFF";length=9;text_color=DIM;end
     else if(state[52])begin text="TOUCH ERROR";length=11;text_color=RED;end
     else if(!state[51])begin text="TOUCH WAIT";length=10;text_color=AMBER;end
     else if(!state[50])begin text="TOUCH MONITOR";length=13;text_color=AMBER;end
     else begin text="TOUCH READY";length=11;text_color=GREEN;end
     tx=24;
    end else begin text=menu?"MATRIX CONTROLS":"MATRIX PLAYS";length=menu?15:12;tx=216;text_color=menu?CYAN:DIM;end
   end else begin text=menu?"R3 PARAMS  R4C4 PLAY":"S0 HOLD FOR MENU";length=menu?20:16;tx=216;ty=454;text_color=DIM;end
  end
  dx=integer'(x)-tx;dy=integer'(y)-ty;
  if(length>0 && dx>=0 && dy>=0 && dy<7*scale && dx<length*6*scale)begin
   if(scale==3)begin char_index=dx/18;col=(dx%18)/3;row=dy/3;end
   else begin char_index=dx/12;col=(dx%12)/2;row=dy/2;end
   character=text[(length-1-char_index)*8+:8];
   if(col<5)begin ink=1;bit_index=34-row*5-col;end
  end
  if(state[19])begin
   case(x/100)
    0:base=24'hffffff;1:base=24'hffff00;2:base=24'h00ffff;3:base=24'h00ff00;
    4:base=24'hff00ff;5:base=24'hff0000;6:base=24'h0000ff;default:base=0;
   endcase
   if(x==0 || x==799 || y==0 || y==479)base=WHITE;
   ink=0;
  end
  if(!de_in || x>=800 || y>=480)begin base=0;ink=0;end
 end
 always @(posedge pixel_clk)begin
  if(rst)begin
   state<=0;base_pipe<=0;text_pipe<=0;char_pipe<=0;bit_pipe<=0;ink_pipe<=0;
   de_pipe<=0;hs_pipe<=0;vs_pipe<=0;rgb<=0;de_out<=0;hs_out<=0;vs_out<=0;
  end else begin
   if(frame_start && status_valid)state<=status_data;
   base_pipe<=base;text_pipe<=text_color;char_pipe<=character;bit_pipe<=bit_index;ink_pipe<=ink;
   de_pipe<=de_in && x<800 && y<480;hs_pipe<=hs_in;vs_pipe<=vs_in;
   rgb<=ink_pipe && glyph_bits[bit_pipe]?text_pipe:base_pipe;
   de_out<=de_pipe;hs_out<=hs_pipe;vs_out<=vs_pipe;
  end
 end
endmodule
