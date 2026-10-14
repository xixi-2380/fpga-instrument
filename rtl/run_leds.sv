`timescale 1ns/1ps
`include "run_leds_config.svh"
module run_leds #(parameter integer STEP_CYCLES=`RUN_LED_STEP_CYCLES)(
    input wire clk,audio_ready_async,key_active_async,
    output wire [5:0] led_n);
    localparam integer CW=STEP_CYCLES>1?$clog2(STEP_CYCLES):1;
    // Gowin configuration/GSR initializes these registers. The run indicator
    // deliberately continues during user reset and audio PLL loss.
    reg [CW-1:0] count=0;
    reg [1:0] position=0;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] ready_sync=0,key_sync=0;
    always @(posedge clk)begin
        ready_sync<={ready_sync[0],audio_ready_async};
        key_sync<={key_sync[0],key_active_async};
        if(count==STEP_CYCLES-1)begin count<=0;position<=position+1'b1;end
        else count<=count+1'b1;
    end
    assign led_n[3:0]=~(4'b0001<<position);
    assign led_n[4]=~ready_sync[1];
    assign led_n[5]=~key_sync[1];
    // synthesis translate_off
    initial if(STEP_CYCLES<1)$fatal(1,"Invalid LED step interval");
    // synthesis translate_on
endmodule
