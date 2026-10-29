`timescale 1ns/1ps
`include "check.svh"
module tb_i2c_register_master;
    reg clk=0,rst=1,start=0,reading=1;
    always #10 clk=~clk;
    reg [15:0] address=16'h8140;
    reg [3:0] length=1;
    tri1 scl,sda;
    reg hold_scl=0,hold_sda=0;
    wire scl_low,sda_low,busy,done,error;
    wire [71:0] data;
    assign scl=(scl_low || hold_scl)?1'b0:1'bz;
    assign sda=(sda_low || hold_sda)?1'b0:1'bz;
    integer checks=0,cycles=0,done_count=0;
    reg prior_done=0;
    i2c_register_master #(.HALF_CYCLES(4),.TIMEOUT_CYCLES(64))
        dut(clk,rst,start,reading,address,8'd0,length,scl,sda,scl_low,sda_low,busy,done,error,data,,);
    always @(posedge clk)begin
        #1;
        `CHECK(!(done && prior_done),"done is a single clock pulse")
        prior_done=done;
        if(done)done_count=done_count+1;
    end
    task request(input [3:0] bytes);
        begin @(negedge clk);length=bytes;start=1;@(negedge clk);start=0;end
    endtask
    task wait_completion;
        begin
            cycles=0;
            while(!done && cycles<1000)begin @(negedge clk);cycles=cycles+1;end
            `CHECK(done && !busy && error,"failed transaction completes within bounded cycles")
            `CHECK(!scl_low && !sda_low,"failure releases bus ownership")
        end
    endtask
    initial begin
        #100;rst=0;
        request(0);`CHECK(done && error && !busy,"zero-length read rejected without starting bus")
        repeat(3)@(negedge clk);
        request(10);`CHECK(done && error && !busy,"oversized read rejected without starting bus")
        repeat(3)@(negedge clk);
        // No device ACKs: STOP and timeout must both terminate cleanly.
        request(1);wait_completion();
        repeat(3)@(negedge clk);
        hold_sda=1;request(1);wait_completion();hold_sda=0;
        repeat(3)@(negedge clk);
        hold_scl=1;request(1);wait_completion();hold_scl=0;
        repeat(3)@(negedge clk);
        request(1);wait(dut.state==18);hold_sda=1;
        wait_completion();hold_sda=0;
        repeat(3)@(negedge clk);
        request(9);wait(scl_low);
        @(negedge clk);start=1;address=16'hffff;
        @(negedge clk);start=0;
        `CHECK(dut.address==16'h8140,"busy master ignores unsolicited command")
        #3;rst=1;#2;
        `CHECK(!busy && !done && !error && !scl_low && !sda_low,"reset during byte aborts and releases both lines")
        `CHECK(done_count==6,"every rejected command reports exactly one completion")
        $display("PASS tb_i2c_register_master checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"I2C master timeout");end
endmodule
