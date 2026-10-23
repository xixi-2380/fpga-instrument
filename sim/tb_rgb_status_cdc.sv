`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_status_cdc;
    parameter integer SOURCE_HALF=7,PIXEL_HALF=11,WIDTH=20;
    reg sc=0,pc=0,reset=0,source_run=1,pixel_run=1;
    always #(SOURCE_HALF) if(source_run)sc=~sc;else sc=0;
    always #(PIXEL_HALF) if(pixel_run)pc=~pc;else pc=0;
    reg [9:0] serial=0;
    wire [((WIDTH+19)/20)*20-1:0] pattern={((WIDTH+19)/20){serial,~serial}};
    wire [WIDTH-1:0] data=pattern[WIDTH-1:0];
    wire [WIDTH-1:0] received;
    wire valid,pulse;
    reg [WIDTH-1:0] expected=0,old_received=0,old_held=0;
    reg old_ack=0,old_pulse=0;
    integer checks=0,updates=0,captures=0;
    rgb_status_cdc #(.WIDTH(WIDTH)) dut(sc,pc,reset,data,received,valid,pulse);
    always @(posedge sc)begin
        serial<=serial+1'b1;
        if(!reset && !dut.source_reset && !dut.acknowledge && dut.request_sync[1])begin
            expected=data;captures=captures+1;
        end
        #1;
        if(!reset && !dut.source_reset && old_ack && dut.acknowledge)
            `CHECK(dut.held_data==old_held,"bundled source payload held throughout ACK")
        old_ack=dut.acknowledge;old_held=dut.held_data;
    end
    always @(posedge pc)begin
        #2;
        if(reset || dut.pixel_reset)begin
            `CHECK(!valid && !pulse && received==0,"reset clears validity and old payload")
        end else begin
            `CHECK(!(old_pulse && pulse),"update is a single pixel-clock pulse")
            if(pulse)begin
                updates=updates+1;
                `CHECK(valid && received===expected,"received snapshot equals complete source capture")
                `CHECK(received[9:0]==~received[19:10],"rapid multi-bit changes never tear a snapshot")
            end else `CHECK(received===old_received,"payload stable between completed transfers")
        end
        old_pulse=pulse;old_received=received;
    end
    task restart;
        begin
            #3;reset=1;#2;
            `CHECK(!valid && !pulse && received==0,"asynchronous reset acts without a clock")
            repeat(5)@(negedge pc);
            reset=0;
            repeat(40)@(negedge pc);
            `CHECK(valid,"handshake restarts after reset")
        end
    endtask
    initial begin
        restart();
        repeat(1200)@(negedge pc);
        // Pause the display while the source continues changing at full speed.
        @(negedge pc);pixel_run=0;
        repeat(80)@(negedge sc);
        pixel_run=1;
        repeat(60)@(negedge pc);
        `CHECK(valid,"pixel clock restart recovers without source backpressure")
        // Pause source during a request and then recover.
        @(negedge sc);source_run=0;
        repeat(80)@(negedge pc);
        source_run=1;
        repeat(60)@(negedge pc);
        restart();
        // Reset at varied phases, including capture and return-to-zero phases.
        repeat(9)begin repeat(7)@(negedge pc);restart();end
        `CHECK(updates>20 && captures>=updates,"many snapshots completed at asynchronous clock ratio")
        $display("PASS tb_rgb_status_cdc checks=%0d updates=%0d width=%0d",checks,updates,WIDTH);$finish;
    end
    initial begin #1000000;$fatal(1,"CDC timeout");end
endmodule

