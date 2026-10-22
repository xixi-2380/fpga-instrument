`timescale 1ns/1ps
`include "config/synth_config.svh"
// Independent active-low Dock S0..S3 buttons; no matrix-keyboard dependency.
module timbre_control #(parameter integer DEBOUNCE_CYCLES=(`AUDIO_HZ/100),
    LONG_PRESS_CYCLES=(`AUDIO_HZ*4/5))(
    input wire clk,rst,input wire [3:0] buttons_n,
    output reg [1:0] selected,output reg effects_enabled,output reg [1:0] effect_mode);
    localparam integer CW=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1;
    (* async_reg="true" *) reg [3:0] sync_meta,sync_buttons;
    reg [3:0] stable_buttons,press_event,release_event;
    localparam integer HW=LONG_PRESS_CYCLES>1?$clog2(LONG_PRESS_CYCLES):1;
    reg [HW-1:0] hold_count;
    reg holding,long_fired;
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
        if(rst)begin selected<=0;effects_enabled<=0;effect_mode<=0;hold_count<=0;holding<=0;long_fired<=0;end
        else begin
            // Simultaneous preset presses: lower button number wins.
            if(press_event[0])selected<=0;
            else if(press_event[1])selected<=1;
            else if(press_event[2])selected<=2;
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
