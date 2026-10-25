`timescale 1ns/1ps
`include "config/synth_config.svh"
module lock_guard #(parameter integer STABLE_CYCLES=`LOCK_CYCLES)(
    input wire clk,rst,lock_async,output reg qualified);
    localparam integer CW=STABLE_CYCLES>1?$clog2(STABLE_CYCLES+1):1;
    wire arst=rst | ~lock_async;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] lock_sync;
    reg [CW-1:0] count;
    reg terminal;
    // Existing two-cycle lock qualifier also synchronizes counter reset release.
    wire count_reset=~lock_sync[1];
    always @(posedge clk or posedge arst)
        if(arst)lock_sync<=0;else lock_sync<={lock_sync[0],1'b1};
    generate if(CW>8)begin: split_counter
        reg carry8;
        always @(posedge clk or posedge count_reset)begin
            if(count_reset)begin count<=0;carry8<=0;end
            else if(!qualified && !terminal)begin
                // Carry is predicted at low byte FE for the NEXT increment.
                // Both slices still represent the exact original binary count.
                count[7:0]<=count[7:0]+1'b1;
                count[CW-1:8]<=count[CW-1:8]+carry8;
                carry8<=count[7:0]==8'hfe;
            end
        end
    end else begin: small_counter
        always @(posedge clk or posedge count_reset)
            if(count_reset)count<=0;
            else if(!qualified && !terminal)count<=count+1'b1;
    end endgenerate
    always @(posedge clk or posedge count_reset)begin
        if(count_reset)begin qualified<=0;terminal<=STABLE_CYCLES==1;end
        else if(!qualified)begin
            if(terminal)qualified<=1;
            else terminal<=count==STABLE_CYCLES-2;
        end
    end
    // synthesis translate_off
    initial if(STABLE_CYCLES<1)$fatal(1,"Invalid lock qualification count");
    // synthesis translate_on
endmodule
