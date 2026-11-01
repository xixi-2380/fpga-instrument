`ifndef TOUCH_KEYBOARD_FIXTURE_SVH
`define TOUCH_KEYBOARD_FIXTURE_SVH
`include "aip5916_model.svh"
module touch_keyboard_fixture(input wire rst,input wire [35:0] piano,input wire [11:0] aux,
 input wire [2:0] present,inout wire [2:0] scl,sda,output wire [2:0] int_n);
 for(genvar b=0;b<3;b++)begin: boards
  aip5916_model chip(rst,present[b],{aux[b*4+:4],piano[b*12+:12]},scl[b],sda[b],int_n[b]);
 end
endmodule
`endif
