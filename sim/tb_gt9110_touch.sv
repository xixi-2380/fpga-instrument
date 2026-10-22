`timescale 1ns/1ps
`include "check.svh"
module tb_gt9110_touch;
    parameter integer HALF=4;
    reg clk=0,rst=1;always #10 clk=~clk;
    tri1 scl,sda,irq,reset_n;
    reg slave_sda_low=0,slave_scl_low=0;
    assign sda=slave_sda_low?1'b0:1'bz;
    assign scl=slave_scl_low?1'b0:1'bz;
    wire ready,error,down,pulse;
    wire [3:0] count;
    wire [15:0] x,y,size,rx,ry;
    wire [7:0] id;
    wire [31:0] product;
    integer checks=0,reports=0,clears=0,i,timing_samples=0;
    reg [7:0] byte_value;
    reg [71:0] payload;
    realtime previous_fall=0,previous_rise=0,reset_release,int_release,last_sda_change=0;
    gt9110_touch #(.RESET_CYCLES(20),.STRAP_CYCLES(8),.BOOT_CYCLES(12),
        .POLL_CYCLES(20),.I2C_HALF_CYCLES(HALF),.I2C_TIMEOUT_CYCLES(HALF*20))
        dut(clk,rst,scl,sda,irq,reset_n,ready,error,down,pulse,count,x,y,size,id,product,rx,ry);
    always @(posedge clk)begin
        #1;
        if(pulse)reports=reports+1;
        if(!rst)begin
            `CHECK(dut.bus.scl_low===1'b0 || scl===1'b0,"SCL only driven low")
            `CHECK(dut.bus.sda_low===1'b0 || sda===1'b0,"SDA only driven low")
        end
    end
    always @(negedge scl)begin
        if(previous_rise!=0 && !rst)
            `CHECK($realtime-previous_rise>=HALF*20,"I2C high period meets half-cycle budget")
        previous_fall=$realtime;
    end
    always @(posedge scl)begin
        if(previous_fall!=0 && !rst)
            `CHECK($realtime-previous_fall>=HALF*20,"I2C low period meets half-cycle budget")
        previous_rise=$realtime;
        if(!rst && dut.bus.state==4 && last_sda_change!=0)
            `CHECK($realtime-last_sda_change>=(HALF-(HALF+9)/10)*20,"master write-data setup inside low interval")
    end
    always @(posedge sda or negedge sda)begin
        if(!rst && dut.bus.state==3 && previous_fall!=0)begin
            `CHECK($realtime-previous_fall>=((HALF+9)/10)*20,"master write-data held after SCL falling edge")
            timing_samples=timing_samples+1;
        end
        last_sda_change=$realtime;
    end
    task start_condition;
        begin
            @(negedge sda);
            while(scl!==1'b1)@(negedge sda);
            `CHECK(scl===1'b1,"START or repeated START holds SCL high")
        end
    endtask
    task stop_condition;
        begin
            @(posedge sda);
            while(scl!==1'b1)@(posedge sda);
            `CHECK(scl===1'b1,"STOP releases SDA while SCL high")
        end
    endtask
    task receive_byte;
        integer bitn;
        begin
            byte_value=0;
            for(bitn=7;bitn>=0;bitn=bitn-1)begin @(posedge scl);byte_value[bitn]=sda;end
        end
    endtask
    task acknowledge(input bit accepted);
        begin
            @(negedge scl);slave_sda_low=accepted;
            @(posedge scl);@(negedge scl);slave_sda_low=0;
        end
    endtask
    task send_byte(input [7:0] value,input bit last);
        integer bitn;
        begin
            for(bitn=7;bitn>=0;bitn=bitn-1)begin
                slave_sda_low=!value[bitn];@(posedge scl);@(negedge scl);
            end
            slave_sda_low=0;@(posedge scl);
            `CHECK(sda===last,"master ACKs intermediate bytes and NACKs final byte")
            @(negedge scl);
        end
    endtask
    task read_transaction(input [15:0] address,input integer length,input [71:0] bytes,input bit stretch);
        integer byte_index;
        begin
            start_condition();receive_byte();
            `CHECK(byte_value==8'hba,"7-bit 5D write address")
            acknowledge(1);receive_byte();`CHECK(byte_value==address[15:8],"register address high byte first")
            acknowledge(1);receive_byte();`CHECK(byte_value==address[7:0],"register address low byte second")
            acknowledge(1);
            if(stretch)begin
                slave_scl_low=1;
                repeat(HALF*4)@(negedge clk);
                slave_scl_low=0;
            end
            start_condition();receive_byte();`CHECK(byte_value==8'hbb,"repeated START uses read address")
            acknowledge(1);
            for(byte_index=0;byte_index<length;byte_index=byte_index+1)
                send_byte(bytes[byte_index*8+:8],byte_index==length-1);
            stop_condition();
        end
    endtask
    task clear_status(input bit accepted);
        begin
            start_condition();receive_byte();`CHECK(byte_value==8'hba,"clear write address")
            acknowledge(1);receive_byte();`CHECK(byte_value==8'h81,"clear register high")
            acknowledge(1);receive_byte();`CHECK(byte_value==8'h4e,"clear register low")
            acknowledge(1);receive_byte();`CHECK(byte_value==0,"only consumed status is written, no config writes")
            `CHECK(!pulse,"new coordinates not published before status-clear ACK")
            acknowledge(accepted);stop_condition();clears=clears+1;
        end
    endtask
    task nack_read_phase(input integer phase);
        begin
            start_condition();receive_byte();`CHECK(byte_value==8'hba,"retry starts at write address")
            acknowledge(1);receive_byte();`CHECK(byte_value==8'h81,"ID register high")
            acknowledge(phase!=1);
            if(phase!=1)begin
                receive_byte();`CHECK(byte_value==8'h40,"ID register low")
                acknowledge(phase!=2);
                if(phase!=2)begin
                    start_condition();receive_byte();`CHECK(byte_value==8'hbb,"ID repeated read address")
                    acknowledge(0);
                end
            end
            stop_condition();
        end
    endtask
    initial begin
        #100;rst=0;
        @(posedge reset_n);reset_release=$realtime;
        `CHECK(irq===1'b0,"INT low straps 5D before reset release")
        @(posedge irq);int_release=$realtime;
        `CHECK(int_release-reset_release==8*20,"INT retained through complete strap delay")
        // Initial address NACK, then hot-plug/retry recovers without resetting FPGA.
        start_condition();receive_byte();`CHECK(byte_value==8'hba,"first attempted address")
        acknowledge(0);stop_condition();wait(error);
        `CHECK(!ready && !down && count==0,"absent controller reports error without false touch")
        nack_read_phase(1);nack_read_phase(2);nack_read_phase(3);
        read_transaction(16'h8140,4,72'h000000000030313139,1);
        read_transaction(16'h8146,4,72'h000000000001e00320,0);
        wait(ready);`CHECK(product==32'h30313139 && rx==800 && ry==480,"ID and resolution read without sensor reconfiguration")
        // No fresh frame: keep untouched and do not clear status.
        read_transaction(16'h814e,9,0,0);
        payload={8'd0,16'd32,16'd123,16'd456,8'd7,8'h81};
        read_transaction(16'h814e,9,payload,0);
        `CHECK(!down,"complete data waits for clear transaction")
        clear_status(1);wait(pulse);#2;
        `CHECK(down && count==1 && x==456 && y==123 && size==32 && id==7,"little-endian first point decoded atomically")
        // Ten reported contacts; first point only is intentionally exported.
        payload={8'd0,16'd44,16'd479,16'd799,8'd9,8'h8a};
        read_transaction(16'h814e,9,payload,0);clear_status(1);wait(pulse);#2;
        `CHECK(count==10 && down && x==799 && y==479 && id==9,"ten-contact status and screen corner retained")
        // Failed status clear must not publish candidate coordinates.
        payload={8'd0,16'd1,16'd20,16'd10,8'd1,8'h81};
        read_transaction(16'h814e,9,payload,0);clear_status(0);wait(error);#2;
        `CHECK(!down && count==0 && x==799,"clear NACK clears pressed state and preserves last confirmed coordinate")
        // Corrupt count is consumed but not reported as a valid touch.
        payload=72'h00000000000000008f;
        read_transaction(16'h814e,9,payload,0);clear_status(1);wait(pulse);#2;
        `CHECK(error && !down && count==0,"invalid point count rejected")
        // Fresh zero-count status is a release, not a stale-data poll.
        read_transaction(16'h814e,9,72'h80,0);clear_status(1);wait(pulse);#2;
        `CHECK(!error && !down && count==0 && x==0 && y==0,"release report clears coordinates and recovers error")
        // Hold SCL low on next transaction: bounded timeout releases ownership.
        slave_scl_low=1;wait(error);#2;
        `CHECK(!dut.bus.busy && !dut.bus.scl_low && !dut.bus.sda_low,"stuck bus times out and releases both pins")
        slave_scl_low=0;
        #3;rst=1;#2;
        `CHECK(!ready && !down && !error && reset_n==0 && irq==0,"USR reset restarts touch initialization safely")
        `CHECK(reports>=5 && clears==5,"success, release and failed reports covered")
        `CHECK(timing_samples>10,"write-data hold timing exercised by many transitions")
        $display("PASS tb_gt9110_touch checks=%0d half_cycles=%0d",checks,HALF);$finish;
    end
    initial begin #100000000;$fatal(1,"touch timeout");end
endmodule
