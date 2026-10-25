`timescale 1ns/1ps
module tb_ultrasonic_range;
    parameter integer CLK_HZ=1000000;
    localparam integer HALF_NS=500000000/CLK_HZ;
    reg clk=0; always #HALF_NS clk=~clk;
    reg rst=1, echo=0;
    wire trig,done,valid; wire [8:0] distance; wire [2:0] error;
    ultrasonic_range #(.CLK_HZ(CLK_HZ)) dut(clk,rst,echo,trig,distance,done,valid,error);
    integer tests=0;
    time last_trig=0;
    always @(posedge trig) begin
        if(last_trig!=0 && ($time-last_trig)<60000000) $fatal(1,"Trigger interval <60ms");
        last_trig=$time;
    end
    task response;
        input integer pulse_us, expect_valid, expect_cm, expect_error;
        time start_trig;
        begin
            @(posedge trig); start_trig=$time;
            @(negedge trig);
            if(($time-start_trig)!=20000) $fatal(1,"Trig width must be 20us");
            #300000; echo=1;
            #(pulse_us*1000); echo=0;
            @(posedge done); #1;
            if(valid!==expect_valid || error!==expect_error) $fatal(1,"Validity/error mismatch: valid=%d err=%d",valid,error);
            if(expect_valid && distance!==expect_cm) $fatal(1,"distance %d expected %d",distance,expect_cm);
            tests=tests+1;
        end
    endtask
    initial begin
        #5000; rst=0;
        response(580,1,10,0);
        response(1160,1,20,0);
        response(2320,1,40,0);
        response(290,1,5,0);
        response(116,1,2,0);
        response(23200,1,400,0);
        response(23258,0,0,3); // 401cm
        response(20,0,0,3);    // short glitch
        @(posedge trig); @(posedge done); #1;
        if(valid || error!=1 || distance!=400) $fatal(1,"No-echo timeout must hold last valid distance");
        tests=tests+1;
        @(posedge trig); @(negedge trig); #300000; echo=1;
        @(posedge done); #1;
        if(valid || error!=2) $fatal(1,"Stuck-high timeout");
        tests=tests+1;
        @(posedge done); #1;
        if(valid || error!=4) $fatal(1,"Pre-trigger high check");
        tests=tests+1;
        echo=0;
        response(580,1,10,0); // recovery
        // Reset while an Echo is in flight; no stale sample may escape.
        @(posedge trig); @(negedge trig); #300000; echo=1;
        #200000; rst=1; #1000;
        if(trig || valid || done || distance!=0) $fatal(1,"Reset must cancel in-flight Echo");
        echo=0; #5000; rst=0;
        response(1160,1,20,0);
        $display("PASS tb_ultrasonic_range cases=%0d clk_hz=%0d",tests,CLK_HZ); $finish;
    end
    initial begin #1600000000; $fatal(1,"Global timeout"); end
endmodule
