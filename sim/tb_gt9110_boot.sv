`timescale 1ns/1ps
`include "check.svh"
module tb_gt9110_boot;
    reg clk=0,rst=1;always #10 clk=~clk;
    tri1 scl,sda,irq,reset_n;
    integer checks=0;
    realtime origin,reset_release,int_release;
    gt9110_touch dut(.clk(clk),.rst(rst),.touch_scl(scl),.touch_sda(sda),
        .touch_int(irq),.touch_rst_n(reset_n));
    initial begin
        #100;origin=$realtime;rst=0;
        @(posedge reset_n);reset_release=$realtime;
        `CHECK(reset_release-origin>=19999980 && reset_release-origin<=20000020,"production reset stays low for 20ms at 50MHz")
        `CHECK(irq===0 && scl===1 && sda===1,"INT low and I2C idle at reset release")
        @(posedge irq);int_release=$realtime;
        `CHECK(int_release-reset_release==6000000,"production INT strap retained for 6ms")
        @(negedge sda);
        `CHECK(scl===1,"first bus operation is START")
        `CHECK($realtime-int_release>=50000000,"boot settle wait is at least 50ms")
        `CHECK($realtime-origin<76020000,"production startup reaches first query near 76ms")
        #3;rst=1;#2;
        `CHECK(reset_n===0 && irq===0 && scl===1 && sda===1,"reset during START releases serial bus and restarts strap")
        $display("PASS tb_gt9110_boot checks=%0d",checks);$finish;
    end
    initial begin #100000000;$fatal(1,"production boot timeout");end
endmodule
