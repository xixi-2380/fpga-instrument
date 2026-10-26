`timescale 1ns/1ps
// Mono delay XY, lag16 original samples from4:1-decimated PCM snapshot.
// 64x64 double buffer, bounded Bresenham; publish only at frame boundaries.
module lissajous_plot(input wire clk,rst,frame_tick,start,input wire [1023:0] waveform,
 input wire read_enable,input wire [5:0] read_x,read_y,output reg pixel,output reg ready);
 localparam [2:0] IDLE=0,CLEAR=1,LOAD=2,SETUP=3,DRAW=4,WAIT_FRAME=5;
 reg [2:0] state;reg display_bank,build_bank,first;
 reg bank0[0:4095],bank1[0:4095];reg [11:0] clear_index;
 reg [1023:0] points;reg [6:0] point_index;reg [5:0] x0,y0,x1,y1;
 reg signed [7:0] dx,dy,err;reg sx,sy;
 wire signed [8:0] e2=$signed({err[7],err})<<<1;
 wire take_x=e2>=$signed(dy),take_y=e2<=$signed(dx);
 wire signed [8:0] next_err=$signed(err)+(take_x?$signed(dy):9'sd0)+(take_y?$signed(dx):9'sd0);
 wire [11:0] waddr=state==CLEAR?clear_index:{y0,x0};wire wen=state==CLEAR||state==DRAW;
 always @(posedge clk)begin
 if(wen)begin if(build_bank)bank1[waddr]<=state==DRAW;else bank0[waddr]<=state==DRAW;end
 pixel<=read_enable&&ready?(display_bank?bank1[{read_y,read_x}]:bank0[{read_y,read_x}]):1'b0;
 end
 wire signed [7:0] source_x=$signed(points[point_index*8+:8]);
 wire signed [7:0] source_y=$signed(points[(point_index-7'd4)*8+:8]);
 always @(posedge clk or posedge rst)begin
 if(rst)begin
 state<=IDLE;display_bank<=0;build_bank<=1;first<=1;ready<=0;
 clear_index<=0;points<=0;point_index<=4;x0<=0;y0<=0;x1<=0;y1<=0;dx<=0;dy<=0;err<=0;sx<=0;sy<=0;
 end else begin
 if(state==WAIT_FRAME&&frame_tick)begin display_bank<=build_bank;ready<=1;state<=IDLE;end
 if(start&&(state==IDLE||(state==WAIT_FRAME&&frame_tick)))begin
 points<=waveform;clear_index<=0;first<=1;point_index<=4;
 build_bank<=state==WAIT_FRAME?display_bank:!display_bank;state<=CLEAR;
 end else case(state)
 CLEAR:if(clear_index==4095)state<=LOAD;else clear_index<=clear_index+1'b1;
 LOAD:begin x1<=8'sd32+(source_x>>>2);y1<=8'sd31-(source_y>>>2);state<=SETUP;end
 SETUP:begin
 if(first)begin x0<=x1;y0<=y1;dx<=0;dy<=0;err<=0;first<=0;end
 else begin
 dx<=x1>=x0?{2'b0,x1}-{2'b0,x0}:{2'b0,x0}-{2'b0,x1};
 dy<=y1>=y0?-$signed({2'b0,y1}-{2'b0,y0}):-$signed({2'b0,y0}-{2'b0,y1});
 err<=$signed(x1>=x0?{2'b0,x1}-{2'b0,x0}:{2'b0,x0}-{2'b0,x1})-
      $signed(y1>=y0?{2'b0,y1}-{2'b0,y0}:{2'b0,y0}-{2'b0,y1});
 sx<=x1>=x0;sy<=y1>=y0;
 end
 state<=DRAW;
 end
 DRAW:begin
 if(x0==x1&&y0==y1)begin if(point_index==127)state<=WAIT_FRAME;else begin point_index<=point_index+1'b1;state<=LOAD;end end
 else begin err<=next_err[7:0];if(take_x)x0<=sx?x0+1'b1:x0-1'b1;if(take_y)y0<=sy?y0+1'b1:y0-1'b1;end
 end
 default:begin end
 endcase
 end
 end
endmodule
