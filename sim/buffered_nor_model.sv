`timescale 1ns/1ps
// Transaction-level NOR model for directory power-cut injection. Independent
// from SPI model; an interrupted mutation keeps only its programmed prefix.
module buffered_nor_model #(parameter integer BYTES=2228224)(
 input wire clk,rst,valid,output wire ready,input wire [1:0] op,input wire [23:0] address,input wire [8:0] length,
 output reg done,output reg [7:0] error,input wire fail_operation,
 input wire bw,input wire [7:0] bi,bd,ri,output reg [7:0] rd);
 reg [7:0] memory[0:BYTES-1],buffer[0:255];reg active=0;
 reg [1:0] operation;reg [23:0] location;integer index,size;
 integer programs=0,erases=0;
 assign ready=!active && !rst;
 initial for(integer k=0;k<BYTES;k++)memory[k]=255;
 always @(posedge clk)begin
  rd<=buffer[ri];
  if(bw && ready)buffer[bi]<=bd;
  if(rst)begin active<=0;done<=0;error<=0;index<=0;size<=0;operation<=0;location<=0;end
  else begin done<=0;
   if(valid && ready)begin
    location<=address;operation<=op;size<=op==3?4096:length;index<=0;active<=1;error<=0;
    if(op==2)programs<=programs+1;if(op==3)erases<=erases+1;
   end else if(active)begin
    if(fail_operation)begin active<=0;error<=8'h22;done<=1;end
    else begin
     if(location+index>=BYTES)$fatal(1,"library crossed NOR bound");
     case(operation)
      1:buffer[index]<=memory[location+index];
      2:memory[location+index]<=memory[location+index]&buffer[index];
      3:memory[location+index]<=255;
      default:$fatal(1,"unexpected library operation");
     endcase
     if(index+1==size)begin active<=0;done<=1;end else index<=index+1;
    end
   end
  end
 end
endmodule
