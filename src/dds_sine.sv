`timescale 1ns/1ps
`include "config/synth_config.svh"
// Independent phase contexts share one synchronous wavetable read port.
module dds_sine #(parameter integer VOICES=1,INDEX_W=VOICES>1?$clog2(VOICES):1)(
    input wire clk,rst,sample_ce,input wire [`PHASE_W-1:0] fcw,
    output wire signed [`ROM_DATA_W-1:0] sample,output reg valid,
    output wire [VOICES*`PHASE_W-1:0] phase,input wire restart,
    input wire [INDEX_W-1:0] voice_index,input wire [2:0] timbre);
    reg [`PHASE_W-1:0] phases[0:VOICES-1];
    wire [`PHASE_W-1:0] sample_phase=restart?{`PHASE_W{1'b0}}:phases[voice_index];
    for(genvar v=0;v<VOICES;v=v+1)begin: context_outputs
        assign phase[v*`PHASE_W+:`PHASE_W]=phases[v];
    end
    wire signed [15:0] sine_sample,flute_sample,reed_sample;
    wire signed [15:0] cello_sample,piano_sample,guitar_sample,vibes_sample;
    reg [2:0] sampled_timbre;
    // An omitted timbre port retains legacy sine behaviour in older adapters.
    always @(posedge clk or posedge rst)
        if(rst)sampled_timbre<=0;
        else if(sample_ce)case(timbre)
            3'd1:sampled_timbre<=1;
            3'd2:sampled_timbre<=2;
                3'd3:sampled_timbre<=3;3'd4:sampled_timbre<=4;3'd5:sampled_timbre<=5;3'd6:sampled_timbre<=6;
            default:sampled_timbre<=0;
        endcase
    assign sample=sampled_timbre==1?flute_sample:
                  sampled_timbre==2 ? reed_sample :
                  sampled_timbre==3 ? cello_sample : sampled_timbre==4 ? piano_sample :
                  sampled_timbre==5 ? guitar_sample : sampled_timbre==6 ? vibes_sample : sine_sample;
    sine_rom #(.ROM_FILE("src/rom/flute4096.hex")) flute_rom(
        .clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[`PHASE_W-1 -: `ROM_ADDR_W]),.q(flute_sample));
    sine_rom #(.ROM_FILE("src/rom/reed4096.hex")) reed_rom(
        .clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[`PHASE_W-1 -: `ROM_ADDR_W]),.q(reed_sample));
    sine_rom #(.ROM_FILE("src/rom/cello4096.hex")) cello_rom(clk,sample_ce && !rst,sample_phase[31:20],cello_sample);
    sine_rom #(.ROM_FILE("src/rom/piano4096.hex")) piano_rom(clk,sample_ce && !rst,sample_phase[31:20],piano_sample);
    sine_rom #(.ROM_FILE("src/rom/guitar4096.hex")) guitar_rom(clk,sample_ce && !rst,sample_phase[31:20],guitar_sample);
    sine_rom #(.ROM_FILE("src/rom/vibraphone4096.hex")) vibes_rom(clk,sample_ce && !rst,sample_phase[31:20],vibes_sample);
    sine_rom rom(.clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[`PHASE_W-1 -: `ROM_ADDR_W]),.q(sine_sample));
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

