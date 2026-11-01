`timescale 1ns/1ps
// Read-only sensor configuration: reads ID/resolution/status/first point and
// clears consumed status. Never rewrites the panel's sensor tuning/configuration.
module gt9110_touch #(
    parameter integer RESET_CYCLES=1000000,STRAP_CYCLES=300000,BOOT_CYCLES=2500000,
    POLL_CYCLES=500000,I2C_HALF_CYCLES=250,I2C_TIMEOUT_CYCLES=50000
)(
    input wire clk,rst,
    inout wire touch_scl,touch_sda,touch_int,touch_rst_n,
    output reg ready,error,touch_down,report_pulse,
    output reg [3:0] touch_count,
    output reg [15:0] touch_x,touch_y,touch_size,
    output reg [7:0] track_id,
    output reg [31:0] product_id,
    output reg [15:0] resolution_x,resolution_y,output reg health_toggle
);
    localparam RESET=0,STRAP=1,BOOT=2,ID_START=3,ID_WAIT=4,RES_START=5,RES_WAIT=6,
        POLL_START=7,POLL_WAIT=8,CLEAR_START=9,CLEAR_WAIT=10,DELAY=11;
    reg [3:0] state,retry_state;
    localparam integer M0=RESET_CYCLES>STRAP_CYCLES?RESET_CYCLES:STRAP_CYCLES;
    localparam integer M1=BOOT_CYCLES>POLL_CYCLES?BOOT_CYCLES:POLL_CYCLES;
    localparam integer MAX_DELAY=M0>M1?M0:M1;
    localparam integer CW=MAX_DELAY>1?$clog2(MAX_DELAY):1;
    reg [CW-1:0] counter;wire [CW-1:0] counter_next;
    for(genvar c=0;c<CW;c=c+8)begin: delay_bytes
        localparam integer W=CW-c<8?CW-c:8;
        (* syn_keep=1 *) wire carry;
        if(c==0)assign carry=1;else assign carry=&counter[c-1:0];
        assign counter_next[c+:W]=counter[c+:W]+carry;
    end
    reg start,read_request;
    reg [15:0] address;
    reg [3:0] length;
    wire scl_low,sda_low,busy,done,bus_error;
    wire [71:0] data;
    reg [3:0] pending_count;
    reg [15:0] pending_x,pending_y,pending_size;
    reg [7:0] pending_id;
    reg pending_bad;
    // Low INT during reset selects 8-bit BA/BB, i.e. 7-bit device address 5D.
    // Release means high impedance: external module pull-ups provide HIGH.
    assign touch_scl=scl_low?1'b0:1'bz;
    assign touch_sda=sda_low?1'b0:1'bz;
    assign touch_rst_n=(rst || state==RESET)?1'b0:1'bz;
    assign touch_int=(rst || state==RESET || state==STRAP)?1'b0:1'bz;
    i2c_register_master #(.HALF_CYCLES(I2C_HALF_CYCLES),.TIMEOUT_CYCLES(I2C_TIMEOUT_CYCLES))
        bus(clk,rst,start,read_request,address,8'd0,length,touch_scl,touch_sda,
            scl_low,sda_low,busy,done,bus_error,data,,);
    task begin_read(input [15:0] reg_addr,input [3:0] bytes,input [3:0] next_state);
        begin address<=reg_addr;length<=bytes;read_request<=1;start<=1;state<=next_state;end
    endtask
    task failed(input [3:0] retry);
        begin
            error<=1;touch_down<=0;touch_count<=0;report_pulse<=1;
            retry_state<=retry;counter<=0;state<=DELAY;
        end
    endtask
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=RESET;retry_state<=ID_START;counter<=0;start<=0;read_request<=1;
            address<=0;length<=1;ready<=0;error<=0;touch_down<=0;report_pulse<=0;
            touch_count<=0;touch_x<=0;touch_y<=0;touch_size<=0;track_id<=0;
            product_id<=0;resolution_x<=0;resolution_y<=0;
            health_toggle<=0;pending_count<=0;pending_x<=0;pending_y<=0;pending_size<=0;pending_id<=0;pending_bad<=0;
        end else begin
            start<=0;report_pulse<=0;
            case(state)
                RESET:if(counter==RESET_CYCLES-1)begin counter<=0;state<=STRAP;end
                    else counter<=counter_next;
                STRAP:if(counter==STRAP_CYCLES-1)begin counter<=0;state<=BOOT;end
                    else counter<=counter_next;
                BOOT:if(counter==BOOT_CYCLES-1)begin counter<=0;state<=ID_START;end
                    else counter<=counter_next;
                ID_START:if(!busy)begin_read(16'h8140,4,ID_WAIT);
                ID_WAIT:if(done)begin
                    if(bus_error)failed(ID_START);
                    else begin product_id<=data[31:0];state<=RES_START;end
                end
                RES_START:if(!busy)begin_read(16'h8146,4,RES_WAIT);
                RES_WAIT:if(done)begin
                    if(bus_error)failed(RES_START);
                    else begin
                        resolution_x<=data[15:0];resolution_y<=data[31:16];
                        ready<=1;error<=0;state<=POLL_START;
                    end
                end
                POLL_START:if(!busy)begin_read(16'h814e,9,POLL_WAIT);
                POLL_WAIT:if(done)begin
                    if(!bus_error)health_toggle<=!health_toggle;
                    if(bus_error)failed(POLL_START);
                    else if(!data[7])begin
                        counter<=0;retry_state<=POLL_START;state<=DELAY;
                    end else begin
                        pending_count<=data[3:0];pending_bad<=data[3:0]>10;
                        pending_id<=data[15:8];pending_x<=data[31:16];
                        pending_y<=data[47:32];pending_size<=data[63:48];state<=CLEAR_START;
                    end
                end
                CLEAR_START:if(!busy)begin
                    address<=16'h814e;length<=1;read_request<=0;start<=1;state<=CLEAR_WAIT;
                end
                CLEAR_WAIT:if(done)begin
                    if(bus_error || pending_bad)failed(POLL_START);
                    else begin
                        touch_count<=pending_count;touch_down<=pending_count!=0;report_pulse<=1;
                        touch_x<=pending_count!=0?pending_x:16'd0;
                        touch_y<=pending_count!=0?pending_y:16'd0;
                        touch_size<=pending_count!=0?pending_size:16'd0;
                        track_id<=pending_count!=0?pending_id:8'd0;error<=0;
                        counter<=0;retry_state<=POLL_START;state<=DELAY;
                    end
                end
                DELAY:if(counter==POLL_CYCLES-1)begin counter<=0;state<=retry_state;end
                    else counter<=counter_next;
                default:begin state<=RESET;counter<=0;ready<=0;touch_down<=0;end
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(RESET_CYCLES<1 || STRAP_CYCLES<1 || BOOT_CYCLES<1 || POLL_CYCLES<1)
        $fatal(1,"GT9110 delay parameters must be positive");
`endif
endmodule
