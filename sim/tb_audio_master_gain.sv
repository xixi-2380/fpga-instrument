`timescale 1ns/1ps
module tb_audio_master_gain;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,ce=0; reg [8:0] target=0;
    reg signed [15:0] sample_in=0;
    wire signed [15:0] sample_out; wire out_valid; wire [8:0] current_gain;
    audio_master_gain dut(clk,rst,target,ce,sample_in,sample_out,out_valid,current_gain);
    integer pending=0,expected=0,next_expected,n,ref_gain=256,ref_count=0,request;
    always @(posedge clk) begin
        if(rst) begin pending=0; expected=0; ref_gain=256; ref_count=0; end else begin
            next_expected=($signed(sample_in)*ref_gain) >>> 8;
            request=(target>256)?256:target;
            if(ce) begin
                if(ref_gain==request) ref_count=0;
                else if(ref_count==3) begin
                    ref_count=0;
                    if(ref_gain<request) ref_gain=ref_gain+1; else ref_gain=ref_gain-1;
                end else ref_count=ref_count+1;
            end
            #1;
            if(out_valid!==pending) $fatal(1,"Audio valid latency");
            if(pending && $signed(sample_out)!==expected) $fatal(1,"PCM mismatch got=%d expected=%d",sample_out,expected);
            if(current_gain!==ref_gain) $fatal(1,"Gain slew mismatch");
            pending=ce; expected=next_expected;
        end
    end
    initial begin
        #25; rst=0;
        for(n=0;n<3400;n=n+1) begin
            @(negedge clk); ce=(n%5!=0);
            case(n%4)
                0: sample_in=32767; 1: sample_in=-32768;
                2: sample_in=12345; 3: sample_in=-12345;
            endcase
            if(n==1400) target=400; // saturates to unity
            if(n==3000) begin rst=1; ce=0; end
            if(n==3002) rst=0;
        end
        @(negedge clk); ce=0;
        repeat(4) @(negedge clk);
        if(current_gain!=256) $fatal(1,"Unity/clamp did not restore gain");
        $display("PASS tb_audio_master_gain cycles=3400 signed/stalls/slew/clamp/reset"); $finish;
    end
endmodule
