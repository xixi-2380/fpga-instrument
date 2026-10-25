`timescale 1ns/1ps
module tb_ultrasonic_volume;
    reg clk=0; always #10 clk=~clk;
    reg rst=1, valid=0; reg [8:0] distance=0;
    wire [8:0] filtered,gain; wire done;
    ultrasonic_volume dut(clk,rst,valid,distance,filtered,gain,done);
    task push;
        input integer cm, expected_cm, expected_gain;
        begin
            @(negedge clk); distance=cm; valid=1;
            @(negedge clk); valid=0;
            if(!done || filtered!==expected_cm || gain!==expected_gain)
                $fatal(1,"median/map mismatch cm=%d filtered=%d gain=%d",cm,filtered,gain);
        end
    endtask
    integer d,expected;
    initial begin
        #25; rst=0;
        if(gain!=256) $fatal(1,"Default gain must be unity");
        push(10,10,219); push(10,10,219); push(200,10,219);
        push(40,40,0); push(40,40,0);
        repeat(5) @(negedge clk);
        if(gain!=0) $fatal(1,"Invalid/no update must hold gain");
        for(d=2;d<=45;d=d+1) begin
            expected=(d<=5)?256:((d>=40)?0:((40-d)*256+17)/35);
            // Two equal samples guarantee median reaches this value.
            @(negedge clk); distance=d; valid=1;
            @(negedge clk); valid=0;
            push(d,d,expected);
        end
        @(negedge clk); rst=1;
        @(negedge clk); rst=0;
        if(gain!=256 || filtered!=0) $fatal(1,"Reset must clear filter history");
        push(20,20,146);
        $display("PASS tb_ultrasonic_volume mapping=2..45 median/hold/reset"); $finish;
    end
endmodule
