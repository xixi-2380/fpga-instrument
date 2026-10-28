`timescale 1ns/1ps
// Mode 0. Only clk clocks logic; sck is a registered output.
module spi_byte_master #(parameter integer HALF_CYCLES=25)(
 input wire clk,rst,valid,input wire [7:0] tx,output wire ready,
 output reg done,output reg [7:0] rx,output reg sck,mosi,input wire miso);
 localparam integer CW=$clog2(HALF_CYCLES+1);
 reg busy;reg [CW-1:0] divider;reg [2:0] bit_no;reg [7:0] shift,received;
 assign ready=!busy && !rst;
 always @(posedge clk or posedge rst)begin
  if(rst)begin busy<=0;divider<=0;bit_no<=7;shift<=0;received<=0;rx<=0;done<=0;sck<=0;mosi<=0;end
  else begin done<=0;
   if(valid && ready)begin busy<=1;divider<=0;bit_no<=7;shift<=tx;received<=0;mosi<=tx[7];end
   else if(busy)begin
    if(divider==HALF_CYCLES-1)begin
     divider<=0;sck<=!sck;
     if(!sck)received<={received[6:0],miso};
     else if(bit_no==0)begin busy<=0;rx<=received;done<=1;end
     else begin bit_no<=bit_no-1'b1;shift<=shift<<1;mosi<=shift[6];end
    end else divider<=divider+1'b1;
   end
  end
 end
 // synthesis translate_off
 initial if(HALF_CYCLES<4)$fatal(1,"SPI half-period must accommodate synchronized MISO");
 // synthesis translate_on
endmodule
