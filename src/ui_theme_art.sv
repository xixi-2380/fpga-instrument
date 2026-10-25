`timescale 1ns/1ps
// Static RGB565 Easter photograph and indexed synchronous ROM artwork. One pixel-clock read stage; no framebuffer,
// external RAM, audio clock access, audio data or backpressure connections.
module ui_theme_art(
 input wire clk,input wire [1:0] theme,input wire [3:0] animation_frame,
 input wire [10:0] x,y,output reg [23:0] pixel,input wire menu);
 reg [3:0] british[0:95999],cat[0:327679],capybara[0:327679];
 reg [15:0] egg[0:29999];
 reg [23:0] british_palette[0:15],cat_palette[0:15],capybara_palette[0:15];
 initial begin
  $readmemh("src/rom/theme_british.hex",british);
  $readmemh("src/rom/theme_cat.hex",cat);
  $readmemh("src/rom/theme_capybara.hex",capybara);
  $readmemh("src/rom/theme_egg.hex",egg);
  $readmemh("src/rom/theme_british_palette.hex",british_palette);
  $readmemh("src/rom/theme_cat_palette.hex",cat_palette);
  $readmemh("src/rom/theme_capybara_palette.hex",capybara_palette);
 end
 integer bg_addr,anim_addr,egg_addr,sx,sy;
 reg sprite_in,picture_in;
 always @*begin
  bg_addr=0;anim_addr=0;egg_addr=0;sprite_in=0;picture_in=0;sx=0;sy=0;
  if(x<800 && y<480)bg_addr=(integer'(y)>>1)*400+(integer'(x)>>1);
  if(x>=500 && x<756 && y>=96 && y<416)begin
   sprite_in=1;anim_addr=integer'(animation_frame)*20480+((integer'(y)-96)>>1)*128+((integer'(x)-500)>>1);
  end
  // One fixed RGB565 photograph, one synchronous read port. There is no
  // foot mask, alternate texture, palette lookup, animation or warp address.
  if(!menu && x>=40 && x<440 && y>=116 && y<416)begin
   picture_in=1;sx=(integer'(x)-40)>>1;sy=(integer'(y)-116)>>1;
  end else if(menu && x>=440 && x<760 && y>=176 && y<416)begin
   picture_in=1;sx=((integer'(x)-440)*5)>>3;sy=((integer'(y)-176)*5)>>3;
  end
  if(picture_in)egg_addr=sy*200+sx;
 end
 reg [3:0] british_q,cat_q,capybara_q;
 reg [15:0] egg_q;
 reg [1:0] theme_q;reg sprite_q,picture_q;
 always @(posedge clk)begin
  british_q<=british[bg_addr];cat_q<=cat[anim_addr];capybara_q<=capybara[anim_addr];
  egg_q<=egg[egg_addr];
  theme_q<=theme;sprite_q<=sprite_in;picture_q<=picture_in;
 end
 always @*begin
  case(theme_q)
   1:pixel=sprite_q && cat_q!=0 ? cat_palette[cat_q] : 24'hf7f1e8;
   2:pixel=sprite_q && capybara_q!=0 ? capybara_palette[capybara_q] : 24'hfff1d9;
   3:pixel=picture_q ? {egg_q[15:11],egg_q[15:13],egg_q[10:5],egg_q[10:9],egg_q[4:0],egg_q[4:2]} : 24'he7e5e3;
   default:pixel=british_palette[british_q];
  endcase
 end
endmodule
