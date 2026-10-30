`timescale 1ns/1ps
// Audio-domain touch settings. Encoders and board buttons are not reassigned.
module rgb_led_settings(input wire clk,rst,menu_mode,action_valid,
 input wire [6:0] action,output reg [15:0] config_data,output wire page);
 `include "config/ui_layout.svh"
 `include "config/rgb_led_config.svh"
 assign page=config_data[15];
 always @(posedge clk or posedge rst)begin
  if(rst)config_data<=RGB_DEFAULTS;
  else begin
   if(!menu_mode)config_data[15]<=0;
   if(action_valid)begin
    if(action==UI_DEFAULTS)config_data<=RGB_DEFAULTS;
    else if(menu_mode)begin
     case(action)
      UI_RGB_OPEN:config_data[15]<=1;
      UI_RGB_BACK,UI_MODE,UI_ULTRA_OPEN,UI_PCB_OPEN,UI_OPEN_MORE:config_data[15]<=0;
      UI_RGB_TOGGLE:if(page)config_data[14]<=!config_data[14];
      UI_RGB_STATIC,UI_RGB_BREATH,UI_RGB_RAINBOW,UI_RGB_KEYS:if(page)config_data[13:12]<=action-UI_RGB_STATIC;
      UI_RGB_DOWN:if(page)config_data[8:2]<=config_data[8:2]>=5?config_data[8:2]-7'd5:7'd0;
      UI_RGB_UP:if(page)config_data[8:2]<=config_data[8:2]<=95?config_data[8:2]+7'd5:7'd100;
      UI_RGB_REVERSE:if(page)config_data[1]<=!config_data[1];
      default:if(page && action>=UI_RGB_COLOR && action<UI_RGB_COLOR+8)config_data[11:9]<=action-UI_RGB_COLOR;
     endcase
    end
   end
  end
 end
endmodule
