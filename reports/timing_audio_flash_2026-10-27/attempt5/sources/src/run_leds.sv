`timescale 1ns/1ps
`include "config/run_leds_config.svh"
module run_leds #(
    parameter integer STEP_CYCLES=`RUN_LED_STEP_CYCLES,
    DIAG_STEPS=`RUN_LED_DIAG_STEPS)(
    input wire clk,audio_ready_async,key_active_async,
    input wire pll1_lock_async,pll2_lock_async,reset_active_async,
    output wire [5:0] led_n);
    localparam integer CW=STEP_CYCLES>1?$clog2(STEP_CYCLES):1;
    localparam integer DW=DIAG_STEPS>0?$clog2(DIAG_STEPS+1):1;
    // Configuration/GSR initializes this reference-clock-only observer.
    // No diagnostic signal feeds back into PLL, reset, keyboard or audio.
    reg [CW-1:0] count=0;
    reg [1:0] position=0;
    reg [DW-1:0] waiting_steps=0;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] ready_sync=0,key_sync=0;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] lock1_sync=0,lock2_sync=0,button_sync=0;
    wire step_tick=(count==STEP_CYCLES-1);
    wire diagnostic_active=(DIAG_STEPS>0) && !ready_sync[1] && (waiting_steps==DIAG_STEPS);
    wire [3:0] run_n=~(4'b0001<<position);
    // Logical LED0 heartbeat, LED1/2 raw lock indications, LED3 reset input.
    // A visibly steady lock LED does not exclude sub-cycle LOCK glitches.
    wire [3:0] diagnostic_n={~button_sync[1],~lock2_sync[1],~lock1_sync[1],~position[0]};
    always @(posedge clk)begin
        ready_sync<={ready_sync[0],audio_ready_async};
        key_sync<={key_sync[0],key_active_async};
        lock1_sync<={lock1_sync[0],pll1_lock_async};
        lock2_sync<={lock2_sync[0],pll2_lock_async};
        button_sync<={button_sync[0],reset_active_async};
        if(step_tick)begin count<=0;position<=position+1'b1;end
        else count<=count+1'b1;
        if(ready_sync[1])waiting_steps<=0;
        else if(step_tick && DIAG_STEPS>0 && waiting_steps<DIAG_STEPS)
            waiting_steps<=waiting_steps+1'b1;
    end
    assign led_n[3:0]=diagnostic_active?diagnostic_n:run_n;
    assign led_n[4]=~ready_sync[1];
    assign led_n[5]=~key_sync[1];
    // synthesis translate_off
    initial if(STEP_CYCLES<1 || DIAG_STEPS<0)$fatal(1,"Invalid LED interval/diagnostic delay");
    // synthesis translate_on
endmodule
