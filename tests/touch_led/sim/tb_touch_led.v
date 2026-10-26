`timescale 1ns/1ps
module tb_touch_led;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0, int_n=1;
    tri1 sda, scl;
    reg slave_low=0, scl_stuck=0, ack_enable=1, corrupt_read=0;
    assign sda=slave_low ? 1'b0 : 1'bz;
    assign scl=scl_stuck ? 1'b0 : 1'bz;
    wire led_n;
    touch_led_top #(.CLK_HZ(1000000), .I2C_HZ(25000),
        .POWERUP_CYCLES(100), .FILTER_CYCLES(16)) dut (
        .clk(clk), .rst_n(rst_n), .touch_sda(sda), .touch_scl(scl),
        .touch_int_n(int_n), .led_n(led_n));

    // Behavioral I2C slave. Decode physical bus edges, not DUT state.
    reg [7:0] registers[0:255];
    reg [7:0] received=0, pointer=0, outgoing=0;
    integer bits=0, byte_position=0, sent=0;
    integer writes=0, reads=0, restarts=0, nacks=0;
    reg active=0, ack_phase=0, read_pending=0, sending=0;
    always @(negedge sda) if (scl === 1'b1) begin
        if (active) restarts=restarts+1;
        active=1;
        bits=0; byte_position=0; received=0;
        ack_phase=0; read_pending=0; sending=0;
    end
    always @(posedge sda) if (scl === 1'b1) begin
        active=0; sending=0; ack_phase=0;
    end
    always @(posedge scl) if (active) begin
        if (sending) begin
            if (sent==8) begin
                if (sda !== 1'b1) $fatal(1,"Master must NACK the last read byte");
                nacks=nacks+1;
            end
            sent=sent+1;
        end else if (bits<8) begin
            received={received[6:0],sda};
            bits=bits+1;
        end
    end
    always @(negedge scl) if (active) begin
        if (sending) begin
            if (sent<8) slave_low=!outgoing[7-sent];
            else if (sent==8) slave_low=0;
            else begin sending=0; bits=0; slave_low=0; end
        end else if (bits==8) begin
            if (!ack_phase) begin
                slave_low=ack_enable;
                ack_phase=1;
                if (byte_position==0) begin
                    if (received!=8'hAC && received!=8'hAD)
                        $fatal(1,"Wrong I2C address: %h",received);
                    read_pending=received[0];
                end else if (byte_position==1) pointer=received;
                else if (ack_enable) begin
                    if (pointer!=8'h3A && registers[8'h3A]!=8'h5A)
                        $fatal(1,"Configuration written outside configuration mode");
                    registers[pointer]=received;
                    writes=writes+1;
                end
            end else begin
                slave_low=0;
                ack_phase=0;
                bits=0;
                byte_position=byte_position+1;
                if (read_pending && ack_enable) begin
                    sending=1; sent=0;
                    outgoing=registers[pointer] ^ (corrupt_read ? 8'h01 : 8'h00);
                    slave_low=!outgoing[7];
                    reads=reads+1;
                    read_pending=0;
                end
            end
        end
    end

    task reset_board;
        integer i;
        begin
            rst_n=0;
            int_n=1;
            repeat(5) @(negedge clk);
            active=0; slave_low=0; sending=0; ack_phase=0;
            for(i=0;i<256;i=i+1) registers[i]=0;
            writes=0; reads=0; restarts=0; nacks=0;
            rst_n=1;
        end
    endtask
    task expect_led;
        input expected;
        begin
            repeat(25) @(negedge clk);
            if(led_n !== expected) $fatal(1,"LED expected %b got %b",expected,led_n);
        end
    endtask
    initial begin
        reset_board;
        if(led_n !== 1'b1) $fatal(1,"LED must start off");
        wait(dut.init_ok);
        @(negedge clk);
        if(writes!=25 || reads!=25 || restarts!=25 || nacks!=25)
            $fatal(1,"Missing init/verification transactions %0d %0d %0d %0d",writes,reads,restarts,nacks);
        if(registers[8'h21]!=8'h04 || registers[8'h3A]!=0 ||
           registers[8'h0F]!=8'h04 || registers[8'h2A]!=8'h10)
            $fatal(1,"Wrong final configuration");
        expect_led(1);
        int_n=0;
        repeat(5) @(negedge clk);
        int_n=1;
        expect_led(1); // short glitch must be rejected
        int_n=0;
        expect_led(0);
        repeat(100) @(negedge clk);
        if(led_n!==0) $fatal(1,"Held touch must keep LED on");
        int_n=1;
        expect_led(1);
        $display("PASS: 25 writes/readbacks, repeated START, final NACK, INT filtering, press/hold/release");

        ack_enable=0;
        reset_board;
        wait(dut.init_error);
        int_n=0;
        expect_led(1);
        if(dut.init_ok || sda!==1 || scl!==1) $fatal(1,"NACK must fail init and release bus");
        $display("PASS: missing device/NACK leaves LED off and releases bus");

        ack_enable=1; corrupt_read=1;
        reset_board;
        wait(dut.init_error);
        if(dut.init_ok) $fatal(1,"Readback mismatch must fail init");
        $display("PASS: readback mismatch rejected");

        corrupt_read=0; scl_stuck=1;
        reset_board;
        wait(dut.init_error);
        if(dut.i2c.sda_low || dut.i2c.scl_low) $fatal(1,"Timeout must release outputs");
        scl_stuck=0;
        int_n=0;
        expect_led(1);
        $display("PASS: stuck SCL terminates with timeout, LED stays off");
        $display("ALL TESTS PASSED");
        $finish;
    end
    initial begin
        #30000000;
        $fatal(1,"Test timeout");
    end
endmodule
