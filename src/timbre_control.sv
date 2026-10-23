`timescale 1ns/1ps
`include "config/synth_config.svh"
// Independent active-low Dock S0..S3 buttons; no matrix-keyboard dependency.
module timbre_control #(parameter integer DEBOUNCE_CYCLES=(`AUDIO_HZ/100),
    LONG_PRESS_CYCLES=(`AUDIO_HZ*4/5))(
    input wire clk,rst,input wire [3:0] buttons_n,
    output reg [1:0] selected,output reg effects_enabled,output reg [1:0] effect_mode,
    input wire ui_action_valid,input wire [5:0] ui_action,input wire cfg_ready,
    output reg menu_mode,output reg cfg_valid,
    output reg [8:0] echo_wet,room_wet,tremolo_depth,
    output reg [3:0] cfg_tremolo_rate_hz,
    output reg [6:0] echo_percent,room_percent,depth_percent,
    output reg [3:0] tremolo_rate_hz);
    localparam integer CW=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1;
    (* async_reg="true" *) reg [3:0] sync_meta,sync_buttons;
    reg [3:0] stable_buttons,press_event,release_event;
    localparam integer HW=LONG_PRESS_CYCLES>1?$clog2(LONG_PRESS_CYCLES):1;
    reg [HW-1:0] hold_count;
    reg holding,long_fired;
    reg [HW-1:0] menu_hold;
    reg menu_holding,menu_fired;
    `include "config/ui_layout.svh"
    function automatic [8:0] amount(input [6:0] percent);
        begin case(percent)
            7'd0:amount=9'd0;
            7'd5:amount=9'd13;
            7'd10:amount=9'd26;
            7'd15:amount=9'd38;
            7'd20:amount=9'd51;
            7'd25:amount=9'd64;
            7'd30:amount=9'd77;
            7'd35:amount=9'd90;
            7'd40:amount=9'd102;
            7'd45:amount=9'd115;
            7'd50:amount=9'd128;
            7'd55:amount=9'd141;
            7'd60:amount=9'd154;
            7'd65:amount=9'd166;
            7'd70:amount=9'd179;
            7'd75:amount=9'd192;
            7'd80:amount=9'd205;
            7'd85:amount=9'd218;
            7'd90:amount=9'd230;
            7'd95:amount=9'd243;
            7'd100:amount=9'd256;
            default:amount=9'd64;
        endcase end
    endfunction
    // Hold a submitted tuple under backpressure; coalesce newer UI targets.
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            echo_wet<=64;room_wet<=64;tremolo_depth<=128;cfg_tremolo_rate_hz<=5;cfg_valid<=1;
        end else if(!cfg_valid || cfg_ready)begin
            if(echo_wet!=amount(echo_percent) || room_wet!=amount(room_percent) ||
                tremolo_depth!=amount(depth_percent) || cfg_tremolo_rate_hz!=tremolo_rate_hz)begin
                echo_wet<=amount(echo_percent);room_wet<=amount(room_percent);
                tremolo_depth<=amount(depth_percent);cfg_tremolo_rate_hz<=tremolo_rate_hz;cfg_valid<=1;
            end else cfg_valid<=0;
        end
    end
    wire menu_long=menu_holding && !stable_buttons[0] && !menu_fired && menu_hold==LONG_PRESS_CYCLES-1;
    wire effect_long=holding && !stable_buttons[3] && !long_fired && hold_count==LONG_PRESS_CYCLES-1;
    wire board_event=(|press_event) || (|release_event) || menu_long || effect_long;
    wire [6:0] current_percent=effect_mode==0?echo_percent:effect_mode==1?room_percent:depth_percent;
    always @(posedge clk or posedge rst)begin
        if(rst)begin sync_meta<=4'hf;sync_buttons<=4'hf;end
        else begin sync_meta<=buttons_n;sync_buttons<=sync_meta;end
    end
    for(genvar b=0;b<4;b=b+1)begin: debounce
        reg [CW-1:0] count;
        always @(posedge clk or posedge rst)begin
            if(rst)begin count<=0;stable_buttons[b]<=1'b1;press_event[b]<=0;release_event[b]<=0;end
            else begin
                press_event[b]<=0;release_event[b]<=0;
                if(sync_buttons[b]==stable_buttons[b])count<=0;
                else if(count==DEBOUNCE_CYCLES-1)begin
                    count<=0;stable_buttons[b]<=sync_buttons[b];
                    if(!sync_buttons[b])press_event[b]<=1;else release_event[b]<=1;
                end else count<=count+1'b1;
            end
        end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin selected<=0;effects_enabled<=0;effect_mode<=0;hold_count<=0;holding<=0;long_fired<=0;
            menu_mode<=0;menu_hold<=0;menu_holding<=0;menu_fired<=0;
            echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;
        end
        else begin
            // S0 is a release action so a long menu press preserves timbre.
            // Board events take priority over a simultaneous UI action.
            if(release_event[0] && menu_holding && !menu_fired)selected<=0;
            else if(!press_event[0] && press_event[1])selected<=1;
            else if(!press_event[0] && press_event[2])selected<=2;
            if(press_event[0])begin menu_holding<=1;menu_fired<=0;menu_hold<=0;end
            else if(menu_holding)begin
                if(release_event[0])menu_holding<=0;
                else if(!stable_buttons[0] && !menu_fired)begin
                    if(menu_long)begin menu_mode<=!menu_mode;menu_fired<=1;end
                    else menu_hold<=menu_hold+1'b1;
                end
            end
            if(ui_action_valid && !board_event)begin
                case(ui_action)
                    UI_SINE:selected<=0;UI_FLUTE:selected<=1;UI_REED:selected<=2;
                    UI_ECHO:begin effect_mode<=0;effects_enabled<=1;end
                    UI_ROOM:begin effect_mode<=1;effects_enabled<=1;end
                    UI_TREMOLO:begin effect_mode<=2;effects_enabled<=1;end
                    UI_FX:effects_enabled<=!effects_enabled;
                    UI_MODE:menu_mode<=!menu_mode;
                    UI_LESS,UI_MORE:begin
                        case(effect_mode)
                            0:echo_percent<=ui_action==UI_MORE?(current_percent<100?current_percent+7'd5:7'd100):(current_percent>0?current_percent-7'd5:7'd0);
                            1:room_percent<=ui_action==UI_MORE?(current_percent<100?current_percent+7'd5:7'd100):(current_percent>0?current_percent-7'd5:7'd0);
                            default:depth_percent<=ui_action==UI_MORE?(current_percent<100?current_percent+7'd5:7'd100):(current_percent>0?current_percent-7'd5:7'd0);
                        endcase
                        
                    end
                    UI_SLOWER:if(effect_mode==2)begin
                        if(tremolo_rate_hz>1)tremolo_rate_hz<=tremolo_rate_hz-1'b1;
                    end
                    UI_FASTER:if(effect_mode==2)begin
                        if(tremolo_rate_hz<10)tremolo_rate_hz<=tremolo_rate_hz+1'b1;
                    end
                    UI_DEFAULTS:begin
                        echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;
                        effect_mode<=0;effects_enabled<=0;
                    end
                    default:begin end
                endcase
            end
            if(press_event[3])begin holding<=1;long_fired<=0;hold_count<=0;end
            else if(holding)begin
                if(release_event[3])begin
                    holding<=0;
                    if(!long_fired)effects_enabled<=!effects_enabled;
                end else if(!stable_buttons[3] && !long_fired)begin
                    if(hold_count==LONG_PRESS_CYCLES-1)begin
                        effect_mode<=effect_mode==2?0:effect_mode+1'b1;
                        effects_enabled<=1;long_fired<=1;
                    end else hold_count<=hold_count+1'b1;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(DEBOUNCE_CYCLES<1 || LONG_PRESS_CYCLES<1)$fatal(1,"Button debounce must be at least one cycle");
    // synthesis translate_on
endmodule
