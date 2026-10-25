`timescale 1ns/1ps
// Static RGB565 Easter photograph and indexed synchronous ROM artwork. One pixel-clock read stage; no framebuffer,
// external RAM, audio clock access, audio data or backpressure connections.
module ui_theme_art(
 input wire clk,input wire [1:0] theme,input wire [3:0] animation_frame,
 input wire [10:0] x,y,output reg [23:0] pixel,input wire menu);
 `include "config/theme_storage.svh"
 reg [3:0] british[0:95999],cat[0:CAT_WORDS-1],capybara[0:CAPYBARA_WORDS-1];
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
 integer bg_addr,cat_addr,capybara_addr,egg_addr,sx,sy;
 integer sprite_x,sprite_y;reg cat_in,capybara_in;
 reg sprite_in,picture_in;
 always @*begin
  bg_addr=0;cat_addr=0;capybara_addr=0;egg_addr=0;sprite_in=0;cat_in=0;capybara_in=0;sprite_x=0;sprite_y=0;picture_in=0;sx=0;sy=0;
  if(x<800 && y<480)bg_addr=(integer'(y)>>1)*400+(integer'(x)>>1);
  if(x>=500 && x<756 && y>=96 && y<416)begin
   sprite_in=1;sprite_x=(integer'(x)-500)>>1;sprite_y=(integer'(y)-96)>>1;
   if(sprite_x>=CAT_X && sprite_x<CAT_X+CAT_WIDTH && sprite_y>=CAT_Y && sprite_y<CAT_Y+CAT_HEIGHT)begin
    cat_in=1;cat_addr=cat_frame_base(animation_frame)+(sprite_y-CAT_Y)*CAT_WIDTH+sprite_x-CAT_X;
   end
   if(sprite_x>=CAPYBARA_X && sprite_x<CAPYBARA_X+CAPYBARA_WIDTH && sprite_y>=CAPYBARA_Y && sprite_y<CAPYBARA_Y+CAPYBARA_HEIGHT)begin
    capybara_in=1;capybara_addr=capybara_frame_base(animation_frame)+(sprite_y-CAPYBARA_Y)*CAPYBARA_WIDTH+sprite_x-CAPYBARA_X;
   end
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
 reg [1:0] theme_q;reg sprite_q,picture_q,cat_in_q,capybara_in_q;
 always @(posedge clk)begin
  british_q<=british[bg_addr];cat_q<=cat[cat_addr];capybara_q<=capybara[capybara_addr];
  egg_q<=egg[egg_addr];
  theme_q<=theme;sprite_q<=sprite_in;picture_q<=picture_in;cat_in_q<=cat_in;capybara_in_q<=capybara_in;
 end
 always @*begin
  case(theme_q)
   1:pixel=sprite_q && cat_in_q && cat_q!=0 ? cat_palette[cat_q] : 24'hf7f1e8;
   2:pixel=sprite_q && capybara_in_q && capybara_q!=0 ? capybara_palette[capybara_q] : 24'hfff1d9;
   3:pixel=picture_q ? {egg_q[15:11],egg_q[15:13],egg_q[10:5],egg_q[10:9],egg_q[4:0],egg_q[4:2]} : 24'he7e5e3;
   default:pixel=british_palette[british_q];
  endcase
 end
endmodule
