`timescale 1ns/1ps
module rgb_key_lights(input wire [35:0] keys,input wire [2:0] board_valid,
 output wire [20:0] white_held);
 `include "config/rgb_led_config.svh"
 for(genvar n=0;n<36;n=n+1)begin: physical
  localparam integer W=rgb_white_index(7'(60+n));
  if(W<21)assign white_held[W]=keys[n] && board_valid[n/12];
 end
endmodule
