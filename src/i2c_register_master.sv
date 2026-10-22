`timescale 1ns/1ps
// Single-master, open-drain I2C register transactions: 16-bit register address,
// one-byte writes or 1..9-byte reads, repeated START, clock stretching, timeout.
// All state uses clk + counters; SCL is never an internal clock.
module i2c_register_master #(
    parameter integer HALF_CYCLES=250,TIMEOUT_CYCLES=50000,
    DATA_HOLD_CYCLES=(HALF_CYCLES+9)/10,
    parameter [6:0] DEVICE_ADDR=7'h5d
)(
    input wire clk,rst,start,read_request,
    input wire [15:0] register_addr,
    input wire [7:0] write_data,
    input wire [3:0] read_bytes,
    input wire scl_in,sda_in,
    output reg scl_low,sda_low,busy,done,error,
    output reg [71:0] read_data
);
    localparam IDLE=0,FREE=1,START_HOLD=2,TX_LOW=3,TX_RISE=4,TX_HIGH=5,
        ACK_LOW=6,ACK_RISE=7,ACK_HIGH=8,RX_LOW=9,RX_RISE=10,RX_HIGH=11,
        MACK_LOW=12,MACK_RISE=13,MACK_HIGH=14,RE_LOW=15,RE_RISE=16,RE_HIGH=17,
        STOP_LOW=18,STOP_RISE=19,STOP_HIGH=20,STOP_FREE=21;
    reg [4:0] state;
    reg [31:0] timer,timeout_count;
    reg [15:0] address;
    reg [7:0] tx,rx,write_byte;
    reg [3:0] length,byte_index;
    reg [2:0] bit_index,stage;
    reg reading,repeated;
    reg next_sda_low;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] scl_sync,sda_sync;
    always @(posedge clk or posedge rst)
        if(rst)begin scl_sync<=3;sda_sync<=3;end
        else begin scl_sync<={scl_sync[0],scl_in};sda_sync<={sda_sync[0],sda_in};end

    task low_phase(input bit next_low,input [4:0] next_state);
        begin
            // Hold the observed previous data through SCL falling, then change
            // SDA inside the low interval (default 25 clocks = 0.5us at 50MHz).
            scl_low<=1;sda_low<=!sda_sync[1];next_sda_low<=next_low;
            timer<=HALF_CYCLES-1;state<=next_state;
        end
    endtask
    task send_byte(input [7:0] value,input [2:0] phase);
        begin
            tx<=value;stage<=phase;bit_index<=7;
            low_phase(!value[7],TX_LOW);
        end
    endtask
    task stop_bus;
        begin low_phase(1'b1,STOP_LOW);end
    endtask
    task abort_bus;
        begin scl_low<=0;sda_low<=0;busy<=0;done<=1;error<=1;state<=IDLE;end
    endtask
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=IDLE;timer<=0;timeout_count<=0;address<=0;tx<=0;rx<=0;write_byte<=0;
            length<=0;byte_index<=0;bit_index<=0;stage<=0;reading<=0;repeated<=0;
            next_sda_low<=0;
            scl_low<=0;sda_low<=0;busy<=0;done<=0;error<=0;read_data<=0;
        end else begin
            done<=0;
            case(state)
                IDLE:if(start)begin
                    error<=0;read_data<=0;address<=register_addr;write_byte<=write_data;
                    reading<=read_request;length<=read_bytes;byte_index<=0;repeated<=0;
                    busy<=1;timer<=HALF_CYCLES-1;timeout_count<=0;state<=FREE;
                    if(read_request && (read_bytes<1 || read_bytes>9))abort_bus();
                end
                FREE:begin
                    if(timeout_count==TIMEOUT_CYCLES-1)abort_bus();
                    else begin
                        timeout_count<=timeout_count+1'b1;
                        if(scl_sync[1] && sda_sync[1])begin
                            if(timer==0)begin sda_low<=1;timer<=HALF_CYCLES-1;state<=START_HOLD;end
                            else timer<=timer-1'b1;
                        end else timer<=HALF_CYCLES-1;
                    end
                end
                START_HOLD:if(timer!=0)timer<=timer-1'b1;
                    else if(repeated)send_byte({DEVICE_ADDR,1'b1},3);
                    else send_byte({DEVICE_ADDR,1'b0},0);
                TX_LOW,ACK_LOW,RX_LOW,MACK_LOW,RE_LOW,STOP_LOW:begin
                    if(timer==HALF_CYCLES-DATA_HOLD_CYCLES)sda_low<=next_sda_low;
                    if(timer!=0)timer<=timer-1'b1;
                    else begin
                        scl_low<=0;timeout_count<=0;
                        case(state)
                            TX_LOW:state<=TX_RISE;ACK_LOW:state<=ACK_RISE;
                            RX_LOW:state<=RX_RISE;MACK_LOW:state<=MACK_RISE;
                            RE_LOW:state<=RE_RISE;STOP_LOW:state<=STOP_RISE;
                        endcase
                    end
                end
                TX_RISE,ACK_RISE,RX_RISE,MACK_RISE,RE_RISE,STOP_RISE:begin
                    if(scl_sync[1])begin
                        timer<=HALF_CYCLES-1;
                        case(state)
                            TX_RISE:state<=TX_HIGH;ACK_RISE:state<=ACK_HIGH;
                            RX_RISE:state<=RX_HIGH;MACK_RISE:state<=MACK_HIGH;
                            RE_RISE:state<=RE_HIGH;STOP_RISE:state<=STOP_HIGH;
                        endcase
                    end else if(timeout_count==TIMEOUT_CYCLES-1)abort_bus();
                    else timeout_count<=timeout_count+1'b1;
                end
                TX_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin
                        if(bit_index!=0)begin
                            bit_index<=bit_index-1'b1;low_phase(!tx[bit_index-1],TX_LOW);
                        end else low_phase(1'b0,ACK_LOW);
                    end
                ACK_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else if(sda_sync[1]!==1'b0)begin error<=1;stop_bus();end
                    else case(stage)
                        0:send_byte(address[15:8],1);
                        1:send_byte(address[7:0],2);
                        2:if(reading)begin
                            low_phase(1'b0,RE_LOW);
                        end else send_byte(write_byte,4);
                        3:begin
                            bit_index<=7;rx<=0;low_phase(1'b0,RX_LOW);
                        end
                        4:stop_bus();
                        default:abort_bus();
                    endcase
                RE_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin sda_low<=1;repeated<=1;timer<=HALF_CYCLES-1;state<=START_HOLD;end
                RX_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin
                        rx<={rx[6:0],sda_sync[1]};
                        if(bit_index!=0)begin bit_index<=bit_index-1'b1;low_phase(1'b0,RX_LOW);end
                        else begin
                            read_data[byte_index*8+:8]<={rx[6:0],sda_sync[1]};
                            low_phase(byte_index+1<length,MACK_LOW);
                        end
                    end
                MACK_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else if(byte_index+1==length)stop_bus();
                    else begin
                        byte_index<=byte_index+1'b1;bit_index<=7;
                        rx<=0;low_phase(1'b0,RX_LOW);
                    end
                STOP_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin sda_low<=0;timer<=HALF_CYCLES-1;state<=STOP_FREE;end
                STOP_FREE:if(timer!=0)timer<=timer-1'b1;
                    else if(scl_sync[1]!==1'b1 || sda_sync[1]!==1'b1)abort_bus();
                    else begin busy<=0;done<=1;state<=IDLE;end
                default:abort_bus();
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(HALF_CYCLES<4 || TIMEOUT_CYCLES<HALF_CYCLES*2 ||
        DATA_HOLD_CYCLES<1 || DATA_HOLD_CYCLES>=HALF_CYCLES-1)
        $fatal(1,"I2C half period must cover input synchronization and timeout must allow bus settling");
`endif
endmodule
