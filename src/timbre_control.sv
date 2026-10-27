`timescale 1ns/1ps
`include "config/synth_config.svh"
// Independent active-low Dock S0..S3 buttons; no matrix-keyboard dependency.
module timbre_control #(parameter integer DEBOUNCE_CYCLES=(`AUDIO_HZ/100),
    LONG_PRESS_CYCLES=(`AUDIO_HZ*4/5),ULTRA_SLEW_CYCLES=(`AUDIO_HZ/500))(
    input wire clk,rst,input wire [3:0] buttons_n,
    output reg [2:0] selected,output reg effects_enabled,output reg [1:0] effect_mode,
    input wire ui_action_valid,input wire [5:0] ui_action,input wire cfg_ready,
    output reg menu_mode,output reg cfg_valid,
    output reg [8:0] echo_wet,room_wet,tremolo_depth,
    output reg [3:0] cfg_tremolo_rate_hz,
    output reg [6:0] echo_percent,room_percent,depth_percent,
    output reg [3:0] tremolo_rate_hz,output reg [6:0] volume_percent,
    output reg ultrasonic_page,ultrasonic_enabled,output reg [2:0] ultrasonic_sensitivity,
    output reg [6:0] ultrasonic_min,ultrasonic_max,output reg [7:0] ultrasonic_version,
    input wire auto_valid,input wire [7:0] auto_version,input wire [6:0] auto_target);
    localparam integer CW=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1;
    (* async_reg="true" *) reg [3:0] sync_meta,sync_buttons;
    reg [3:0] stable_buttons,press_event,release_event;
    localparam integer HW=LONG_PRESS_CYCLES>1?$clog2(LONG_PRESS_CYCLES):1;
    reg [HW-1:0] hold_count;
    reg holding,long_fired;
    reg [HW-1:0] menu_hold;
    reg menu_holding,menu_fired;
    reg menu_terminal,effect_terminal;
    wire [HW-1:0] menu_next,hold_next;
    for(genvar h=0;h<HW;h=h+8)begin: hold_bytes
        localparam integer W=HW-h<8?HW-h:8;
        (* syn_keep=1 *) wire menu_carry,effect_carry;
        if(h==0)begin assign menu_carry=1;assign effect_carry=1;end
        else begin assign menu_carry=&menu_hold[h-1:0];assign effect_carry=&hold_count[h-1:0];end
        assign menu_next[h+:W]=menu_hold[h+:W]+menu_carry;
        assign hold_next[h+:W]=hold_count[h+:W]+effect_carry;
    end
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
    wire menu_long=menu_holding && !stable_buttons[0] && !menu_fired && menu_terminal;
    wire effect_long=holding && !stable_buttons[3] && !long_fired && effect_terminal;
    wire board_event=(|press_event) || (|release_event) || menu_long || effect_long;
    wire [6:0] current_percent=effect_mode==0?echo_percent:effect_mode==1?room_percent:depth_percent;
    localparam integer SW=ULTRA_SLEW_CYCLES>1?$clog2(ULTRA_SLEW_CYCLES):1;
    reg [SW-1:0] slew_count;
    wire auto_current=auto_valid===1'b1 && auto_version==ultrasonic_version;
    always @(posedge clk or posedge rst)begin
        if(rst)begin sync_meta<=4'hf;sync_buttons<=4'hf;end
        else begin sync_meta<=buttons_n;sync_buttons<=sync_meta;end
    end
    for(genvar b=0;b<4;b=b+1)begin: debounce
        reg [CW-1:0] count;
        wire [CW-1:0] count_next;
        for(genvar c=0;c<CW;c=c+8)begin: count_bytes
            localparam integer W=CW-c<8?CW-c:8;
            (* syn_keep=1 *) wire carry;
            if(c==0)assign carry=1;else assign carry=&count[c-1:0];
            assign count_next[c+:W]=count[c+:W]+carry;
        end
        always @(posedge clk or posedge rst)begin
            if(rst)begin count<=0;stable_buttons[b]<=1'b1;press_event[b]<=0;release_event[b]<=0;end
            else begin
                press_event[b]<=0;release_event[b]<=0;
                if(sync_buttons[b]==stable_buttons[b])count<=0;
                else if(count==DEBOUNCE_CYCLES-1)begin
                    count<=0;stable_buttons[b]<=sync_buttons[b];
                    if(!sync_buttons[b])press_event[b]<=1;else release_event[b]<=1;
                end else count<=count_next;
            end
        end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin selected<=0;effects_enabled<=0;effect_mode<=0;hold_count<=0;holding<=0;long_fired<=0;
            menu_mode<=0;menu_hold<=0;menu_holding<=0;menu_fired<=0;
            menu_terminal<=LONG_PRESS_CYCLES==1;effect_terminal<=LONG_PRESS_CYCLES==1;
            echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;volume_percent<=100;
            ultrasonic_page<=0;ultrasonic_enabled<=0;ultrasonic_sensitivity<=1;
            ultrasonic_min<=0;ultrasonic_max<=100;ultrasonic_version<=0;slew_count<=0;
        end
        else begin
            // S0 is a release action so a long menu press preserves timbre.
            // Board events take priority over a simultaneous UI action.
            if(release_event[0] && menu_holding && !menu_fired)selected<=0;
            else if(!menu_mode && !press_event[0] && press_event[1])selected<=1;
            else if(!menu_mode && !press_event[0] && press_event[2])selected<=2;
            if(ultrasonic_enabled && auto_current)begin
                if(slew_count==ULTRA_SLEW_CYCLES-1)begin
                    slew_count<=0;
                    if(volume_percent<auto_target)volume_percent<=volume_percent+1'b1;
                    else if(volume_percent>auto_target)volume_percent<=volume_percent-1'b1;
                end else slew_count<=slew_count+1'b1;
            end else slew_count<=0;
            if(menu_mode && !ultrasonic_enabled && press_event[1])volume_percent<=volume_percent>=5 ? volume_percent-7'd5 : 7'd0;
            else if(menu_mode && !ultrasonic_enabled && press_event[2])volume_percent<=volume_percent<=95 ? volume_percent+7'd5 : 7'd100;
            if(press_event[0])begin menu_holding<=1;menu_fired<=0;menu_hold<=0;menu_terminal<=LONG_PRESS_CYCLES==1;end
            else if(menu_holding)begin
                if(release_event[0])menu_holding<=0;
                else if(!stable_buttons[0] && !menu_fired)begin
                    if(menu_long)begin menu_mode<=!menu_mode;ultrasonic_page<=0;menu_fired<=1;end
                    else begin menu_hold<=menu_next;menu_terminal<=menu_hold==LONG_PRESS_CYCLES-2;end
                end
            end
            if(ui_action_valid && !board_event)begin
                case(ui_action)
                    UI_SINE:selected<=0;UI_FLUTE:selected<=1;UI_REED:selected<=2;
                    UI_CELLO:selected<=3;UI_PIANO:selected<=4;UI_GUITAR:selected<=5;UI_VIBES:selected<=6;
                    UI_PREV:if(selected==0)selected<=6;else selected<=selected-1'b1;
                    UI_NEXT:if(selected==6)selected<=0;else selected<=selected+1'b1;
                    UI_ECHO:begin effect_mode<=0;effects_enabled<=1;end
                    UI_ROOM:begin effect_mode<=1;effects_enabled<=1;end
                    UI_TREMOLO:begin effect_mode<=2;effects_enabled<=1;end
                    UI_VOLUME_DOWN:if(!ultrasonic_enabled)volume_percent<=volume_percent>=5 ? volume_percent-7'd5 : 7'd0;
                    UI_VOLUME_UP:if(!ultrasonic_enabled)volume_percent<=volume_percent<=95 ? volume_percent+7'd5 : 7'd100;
                    UI_OPEN_MORE:ultrasonic_page<=0;
                    UI_ULTRA_OPEN:if(menu_mode)ultrasonic_page<=1;
                    UI_ULTRA_BACK:ultrasonic_page<=0;
                    UI_ULTRA_TOGGLE:begin
                        ultrasonic_enabled<=!ultrasonic_enabled;ultrasonic_version<=ultrasonic_version+1'b1;slew_count<=0;
                        // Freeze the exact pre-toggle volume on disable, even at a slew tick.
                        volume_percent<=volume_percent;
                    end
                    UI_SENS_DOWN:if(ultrasonic_sensitivity>1)begin ultrasonic_sensitivity<=ultrasonic_sensitivity-1'b1;ultrasonic_version<=ultrasonic_version+1'b1;end
                    UI_SENS_UP:if(ultrasonic_sensitivity<5)begin ultrasonic_sensitivity<=ultrasonic_sensitivity+1'b1;ultrasonic_version<=ultrasonic_version+1'b1;end
                    UI_MIN_DOWN:if(ultrasonic_min>=5)begin ultrasonic_min<=ultrasonic_min-7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
                    UI_MIN_UP:if(ultrasonic_min+7'd5<=ultrasonic_max)begin ultrasonic_min<=ultrasonic_min+7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
                    UI_MAX_DOWN:if(ultrasonic_max>=ultrasonic_min+7'd5)begin ultrasonic_max<=ultrasonic_max-7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
                    UI_MAX_UP:if(ultrasonic_max<=95)begin ultrasonic_max<=ultrasonic_max+7'd5;ultrasonic_version<=ultrasonic_version+1'b1;end
                    UI_FX:effects_enabled<=!effects_enabled;
                    UI_MODE:begin menu_mode<=!menu_mode;ultrasonic_page<=0;end
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
                        volume_percent<=100;
                        ultrasonic_enabled<=0;ultrasonic_page<=0;ultrasonic_sensitivity<=1;
                        ultrasonic_min<=0;ultrasonic_max<=100;ultrasonic_version<=ultrasonic_version+1'b1;
                        echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;
                        effect_mode<=0;effects_enabled<=0;
                    end
                    default:begin end
                endcase
            end
            if(press_event[3])begin holding<=1;long_fired<=0;hold_count<=0;effect_terminal<=LONG_PRESS_CYCLES==1;end
            else if(holding)begin
                if(release_event[3])begin
                    holding<=0;
                    if(!long_fired)effects_enabled<=!effects_enabled;
                end else if(!stable_buttons[3] && !long_fired)begin
                    if(effect_long)begin
                        effect_mode<=effect_mode==2?0:effect_mode+1'b1;
                        effects_enabled<=1;long_fired<=1;
                    end else begin hold_count<=hold_next;effect_terminal<=hold_count==LONG_PRESS_CYCLES-2;end
                end
            end
        end
    end
    // synthesis translate_off
    initial if(DEBOUNCE_CYCLES<1 || LONG_PRESS_CYCLES<1 || ULTRA_SLEW_CYCLES<1)$fatal(1,"Button/slew interval must be at least one cycle");
    // synthesis translate_on
endmodule
