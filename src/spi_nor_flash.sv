`timescale 1ns/1ps
// U7 only. Buffered 1..256-byte transactions, no chip erase/status writes.
// Known 3.3V W25Q128JV-IQ EF4018 profile; unknown IDs remain read-only.
module spi_nor_flash #(
 parameter integer HALF_CYCLES=25,BOOT_CYCLES=50000,POLL_CYCLES=5000,TIMEOUT_CYCLES=50000000,
 parameter [23:0] REGION_FIRST=24'h000000,REGION_LAST=24'h21ffff)(
 input wire clk,rst,request_valid,output wire request_ready,input wire [1:0] operation,
 input wire [23:0] address,input wire [8:0] length,input wire writes_enabled,
 output reg done,output reg [7:0] error,output reg initialized,output wire supported,
 output reg [23:0] jedec_id,output reg [7:0] status1,status2,status3,
 input wire buffer_write,input wire [7:0] buffer_index,input wire [7:0] buffer_wdata,
 input wire [7:0] read_index,output reg [7:0] read_data,
 output reg cs_n,output wire sck,mosi,input wire miso,output wire wp_n,hold_n);
 // operation:0 probe,1 read,2 page program,3 sector erase.
 localparam [5:0] BOOT=0,IDLE=1,ID=2,ID_DONE=3,SR1=4,SR1_DONE=5,SR2=6,SR2_DONE=7,SR3=8,SR3_DONE=9,
  DISPATCH=10,WREN=11,WREN_DONE=12,WEL=13,WEL_DONE=14,EXEC=15,EXEC_DONE=16,POLL=17,POLL_DONE=18,
  X_PREP=20,X_SEND=21,X_WAIT=22,X_END=23,FINISH=24,BOOT_STATUS=25,BOOT_STATUS_DONE=26,BOOT_POLL=27;
 reg [5:0] state,return_state;reg [31:0] delay_count,timeout_count;
 reg [1:0] op;reg [23:0] location;reg [8:0] size;
 reg [7:0] opcode,spi_tx,received,program_byte;reg [9:0] index,total,capture_first;
 reg with_address;reg [7:0] buffer[0:255];
 (* async_reg="true" *) reg miso_meta,miso_sync;
 wire byte_ready,byte_done;wire [7:0] spi_rx;
 wire write_ok=writes_enabled && supported && status1[7:2]==0 && !status1[0] && !status2[6] && !status2[0] && !status2[7] && !status3[2];
 wire [24:0] last_address={1'b0,location}+{16'd0,size}-1'b1;
 assign supported=jedec_id==24'hef4018;
 assign request_ready=state==IDLE && initialized && !rst;
 assign wp_n=1;assign hold_n=1;
 spi_byte_master #(.HALF_CYCLES(HALF_CYCLES)) bytes(clk,rst,state==X_SEND,spi_tx,byte_ready,byte_done,spi_rx,sck,mosi,miso_sync);
 always @(posedge clk or posedge rst)begin
  if(rst)begin miso_meta<=1;miso_sync<=1;end else begin miso_meta<=miso!==1'b0;miso_sync<=miso_meta;end
 end
 always @(posedge clk)begin
  read_data<=buffer[read_index];program_byte<=buffer[index[7:0]-8'd4];
  if(buffer_write && request_ready)buffer[buffer_index]<=buffer_wdata;
  else if(state==X_WAIT && byte_done && opcode==8'h03 && index>=capture_first)buffer[index[7:0]-8'd4]<=spi_rx;
 end
 task automatic transfer(input [7:0] code,input bit addr,input [8:0] n,input [5:0] next_state);
 begin opcode<=code;with_address<=addr;total<=10'd1+(addr?10'd3:10'd0)+{1'b0,n};capture_first<=addr?4:1;
  index<=0;cs_n<=0;return_state<=next_state;state<=X_PREP;end endtask
 task automatic fail(input [7:0] reason);begin error<=reason;state<=FINISH;cs_n<=1;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=BOOT;return_state<=IDLE;delay_count<=BOOT_CYCLES;timeout_count<=0;initialized<=0;
   done<=0;error<=0;jedec_id<=0;status1<=0;status2<=0;status3<=0;cs_n<=1;
   op<=0;location<=0;size<=0;opcode<=0;received<=0;index<=0;total<=0;capture_first<=0;with_address<=0;end
  else begin done<=0;
   if(state!=IDLE && state!=BOOT && timeout_count<TIMEOUT_CYCLES)timeout_count<=timeout_count+1'b1;
   if(state!=IDLE && state!=BOOT && state!=FINISH && timeout_count>=TIMEOUT_CYCLES && state!=X_SEND && state!=X_WAIT && state!=X_PREP && state!=X_END)fail(8'h22);
   else case(state)
    // USR resets FPGA logic, not the external NOR. Wait for an in-flight
    // program/erase before JEDEC (many devices ignore9F while WIP=1).
    BOOT:if(delay_count==0)begin op<=0;timeout_count<=0;state<=BOOT_STATUS;end else delay_count<=delay_count-1'b1;
    BOOT_STATUS:transfer(8'h05,0,1,BOOT_STATUS_DONE);
    BOOT_STATUS_DONE:begin
     status1<=received;
     if(received[0] && received!=8'hff)begin delay_count<=POLL_CYCLES;state<=BOOT_POLL;end else state<=ID;
    end
    BOOT_POLL:if(delay_count==0)state<=BOOT_STATUS;else delay_count<=delay_count-1'b1;
    IDLE:if(request_valid)begin op<=operation;location<=address;size<=length;error<=0;timeout_count<=0;state<=operation==0?ID:SR1;end
    ID:begin jedec_id<=0;transfer(8'h9f,0,3,ID_DONE);end
    ID_DONE:state<=SR1;
    SR1:transfer(8'h05,0,1,SR1_DONE);
    SR1_DONE:begin status1<=received;state<=SR2;end
    SR2:transfer(8'h35,0,1,SR2_DONE);
    SR2_DONE:begin status2<=received;state<=SR3;end
    SR3:transfer(8'h15,0,1,SR3_DONE);
    SR3_DONE:begin status3<=received;initialized<=1;state<=DISPATCH;end
    DISPATCH:if(op==0)state<=FINISH;
     else if(location<REGION_FIRST || location>REGION_LAST || size==0 || size>256 || last_address>{1'b0,REGION_LAST})fail(8'h23);
     else if(status1[0])fail(8'h25);
     else if(op==1)state<=EXEC;
     else if(!write_ok)fail(8'h21);
     else if(op==2 && ({1'b0,location[7:0]}+size)>256)fail(8'h23);
     else if(op==3 && (location[11:0]!=0 || ({1'b0,location}+25'd4095)>{1'b0,REGION_LAST}))fail(8'h23);
     else state<=WREN;
    WREN:transfer(8'h06,0,0,WREN_DONE);
    WREN_DONE:state<=WEL;
    WEL:transfer(8'h05,0,1,WEL_DONE);
    WEL_DONE:if(received[1] && !received[0] && received[7:2]==0)state<=EXEC;else fail(8'h21);
    EXEC:if(op==1)transfer(8'h03,1,size,EXEC_DONE);
     else if(op==2)transfer(8'h02,1,size,EXEC_DONE);
     else transfer(8'h20,1,0,EXEC_DONE);
    EXEC_DONE:if(op==1)state<=FINISH;else begin delay_count<=POLL_CYCLES;state<=POLL;end
    POLL:if(delay_count==0)transfer(8'h05,0,1,POLL_DONE);else delay_count<=delay_count-1'b1;
    POLL_DONE:begin status1<=received;if(received[0])begin delay_count<=POLL_CYCLES;state<=POLL;end else state<=FINISH;end
    X_PREP:state<=X_SEND;
    X_SEND:if(byte_ready)state<=X_WAIT;
    X_WAIT:if(byte_done)begin
     if(index>=capture_first)begin received<=spi_rx;if(opcode==8'h9f)jedec_id<={jedec_id[15:0],spi_rx};end
     if(index+1==total)begin cs_n<=1;delay_count<=HALF_CYCLES*2;state<=X_END;end
     else begin index<=index+1'b1;state<=X_PREP;end
    end
    X_END:if(delay_count==0)state<=return_state;else delay_count<=delay_count-1'b1;
    FINISH:begin done<=1;initialized<=1;state<=IDLE;end
    default:fail(8'h24);
   endcase
  end
 end
 always @*begin
  spi_tx=0;
  if(index==0)spi_tx=opcode;
  else if(with_address && index<4)case(index)1:spi_tx=location[23:16];2:spi_tx=location[15:8];3:spi_tx=location[7:0];default:spi_tx=0;endcase
  else if(opcode==8'h02)spi_tx=program_byte;
 end
endmodule
