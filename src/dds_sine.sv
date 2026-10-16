`timescale 1ns/1ps
`include "config/synth_config.svh"
// Independent phase contexts share one synchronous wavetable read port.
module dds_sine #(parameter integer VOICES=1,INDEX_W=VOICES>1?$clog2(VOICES):1)(
    input wire clk,rst,sample_ce,input wire [`PHASE_W-1:0] fcw,
    output wire signed [`ROM_DATA_W-1:0] sample,output reg valid,
    output wire [VOICES*`PHASE_W-1:0] phase,input wire restart,
    input wire [INDEX_W-1:0] voice_index);
    reg [`PHASE_W-1:0] phases[0:VOICES-1];
    wire [`PHASE_W-1:0] sample_phase=restart?{`PHASE_W{1'b0}}:phases[voice_index];
    for(genvar v=0;v<VOICES;v=v+1)begin: context_outputs
        assign phase[v*`PHASE_W+:`PHASE_W]=phases[v];
    end
    sine_rom rom(.clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[`PHASE_W-1 -: `ROM_ADDR_W]),.q(sample));
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            valid<=0;
            for(integer v=0;v<VOICES;v=v+1)phases[v]<=0;
        end else begin
            valid<=sample_ce;
            if(sample_ce)phases[voice_index]<=sample_phase+fcw;
        end
    end
    // synthesis translate_off
    always @(posedge clk)if(!rst && sample_ce && voice_index>=VOICES)$fatal(1,"DDS context out of range");
    initial if(VOICES<1 || VOICES>32)$fatal(1,"Invalid DDS voice count");
    // synthesis translate_on
endmodule
