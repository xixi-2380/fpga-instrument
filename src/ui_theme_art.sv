`timescale 1ns/1ps
// Indexed synchronous ROM artwork. One pixel-clock read stage; no framebuffer,
// external RAM, audio clock access, audio data or backpressure connections.
module ui_theme_art(
 input wire clk,input wire [1:0] theme,input wire [3:0] animation_frame,foot_step,
 input wire [10:0] x,y,output reg [23:0] pixel);
 reg [3:0] british[0:95999],cat[0:327679],capybara[0:327679];
 reg [7:0] egg[0:95999];
 reg [23:0] british_palette[0:15],cat_palette[0:15],capybara_palette[0:15],egg_palette[0:31];
 initial begin
  $readmemh("src/rom/theme_british.hex",british);
  $readmemh("src/rom/theme_cat.hex",cat);
  $readmemh("src/rom/theme_capybara.hex",capybara);
  $readmemh("src/rom/theme_egg.hex",egg);
  $readmemh("src/rom/theme_british_palette.hex",british_palette);
  $readmemh("src/rom/theme_cat_palette.hex",cat_palette);
  $readmemh("src/rom/theme_capybara_palette.hex",capybara_palette);
  $readmemh("src/rom/theme_egg_palette.hex",egg_palette);
 end
 integer bg_addr,anim_addr,warp_addr,sx,sy,ix,iy;
 reg sprite_in,warp_in;
 always @*begin
  ix=integer'(x)>>1;iy=integer'(y)>>1;
  bg_addr=0;anim_addr=0;warp_addr=0;sprite_in=0;warp_in=0;
  if(x<800 && y<480)bg_addr=iy*400+ix;
  if(x>=500 && x<756 && y>=96 && y<416)begin
   sprite_in=1;anim_addr=integer'(animation_frame)*20480+((integer'(y)-96)>>1)*128+((integer'(x)-500)>>1);
  end
  // Inverse texture transform around the foot, 1.000 .. 1.062 scale.
  // The other read port retains the original photograph's fixed coordinates.
  sx=280+(((ix-280)*(256-integer'(foot_step)))>>>8);
  sy=176+(((iy-176)*(256-integer'(foot_step)))>>>8);
  if(x<800 && y<480 && sx>=0 && sx<400 && sy>=0 && sy<240)begin
   warp_in=1;warp_addr=sy*400+sx;
  end
 end
 reg [3:0] british_q,cat_q,capybara_q;
 reg [7:0] egg_q,foot_q;
 reg [1:0] theme_q;reg sprite_q,warp_q;
 always @(posedge clk)begin
  british_q<=british[bg_addr];cat_q<=cat[anim_addr];capybara_q<=capybara[anim_addr];
  egg_q<=egg[bg_addr];foot_q<=egg[warp_addr];
  theme_q<=theme;sprite_q<=sprite_in;warp_q<=warp_in;
 end
 always @*begin
  case(theme_q)
   1:pixel=sprite_q && cat_q!=0 ? cat_palette[cat_q] : 24'hf7f1e8;
   2:pixel=sprite_q && capybara_q!=0 ? capybara_palette[capybara_q] : 24'hfff1d9;
   3:pixel=warp_q && foot_q[5] ? egg_palette[foot_q[4:0]] : egg_palette[egg_q[4:0]];
   default:pixel=british_palette[british_q];
  endcase
 end
endmodule
