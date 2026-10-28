`timescale 1ns/1ps
// One AiP5916, one independent 0x56 bus. All accesses use ONE register byte
// and ONE data byte. Polling runs even while INT stays high or low.
module aip5916_keyboard #(
 parameter integer BOOT_CYCLES=500000,POLL_CYCLES=150000,
 I2C_HALF_CYCLES=250,TIMEOUT_CYCLES=50000,RETRY_CYCLES=500000)(
 input wire clk,rst,intr_n,inout wire scl,sda,
 output reg [15:0] keys,output reg online,output reg report,output reg fault);
 localparam BOOT=0,WRITE=1,WRITE_WAIT=2,VERIFY=3,VERIFY_WAIT=4,
 IDLE=5,READ=6,READ_WAIT=7;
 localparam integer MAX_WAIT=BOOT_CYCLES>RETRY_CYCLES?BOOT_CYCLES:RETRY_CYCLES;
 localparam integer BW=MAX_WAIT>1?$clog2(MAX_WAIT):1;
 localparam integer PW=POLL_CYCLES>1?$clog2(POLL_CYCLES):1;
 reg [3:0] state;
 reg [BW-1:0] wait_count;reg [PW-1:0] poll_count;
 reg [4:0] config_index;reg [1:0] byte_index,retries,failures;
 reg [15:0] first_pair;reg [7:0] second_low;
 reg start,reading;reg [15:0] address;reg [7:0] write_byte;
 wire scl_low,sda_low,busy,done,error;wire [71:0] data;
 (* async_reg="true",syn_async_reg=1 *) reg [1:0] int_sync;
 reg previous_int;
 always @(posedge clk or posedge rst)
  if(rst)begin int_sync<=3;previous_int<=1;end
  else begin int_sync<={int_sync[0],intr_n};previous_int<=int_sync[1];end
 assign scl=scl_low?1'b0:1'bz;
 assign sda=sda_low?1'b0:1'bz;
 i2c_register_master #(.HALF_CYCLES(I2C_HALF_CYCLES),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),
  .REGISTER_BYTES(1),.DEVICE_ADDR(7'h56)) bus(
  clk,rst,start,reading,address,write_byte,4'd1,scl,sda,scl_low,sda_low,busy,done,error,data);
 function automatic [7:0] config_address(input [4:0] n);
  begin case(n)
   0,24:config_address=8'h3a;1:config_address=8'h21;
   2:config_address=8'h23;3:config_address=8'h24;4:config_address=8'h20;
   21:config_address=8'h22;22:config_address=8'h2d;23:config_address=8'h2a;
   default:config_address=n-5;
  endcase end
 endfunction
 function automatic [7:0] config_value(input [4:0] n);
  begin case(n)
   0:config_value=8'h5a;1:config_value=8'h04;2,3,22,24:config_value=0;
   4:config_value=2;21:config_value=8'h20;23:config_value=8'h10;
   default:config_value=4;
  endcase end
 endfunction
 task reconnect;
  begin
   keys<=0;online<=0;fault<=1;report<=1;config_index<=0;
   wait_count<=RETRY_CYCLES-1;state<=BOOT;failures<=0;
  end
 endtask
 task bad_poll;
  begin
   if(failures==2)reconnect();
   else begin failures<=failures+1'b1;state<=IDLE;end
  end
 endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=BOOT;wait_count<=BOOT_CYCLES-1;poll_count<=0;config_index<=0;
   byte_index<=0;retries<=0;failures<=0;first_pair<=0;second_low<=0;
   start<=0;reading<=0;address<=0;write_byte<=0;keys<=0;online<=0;report<=0;fault<=0;
  end else begin
   start<=0;report<=0;
   if(poll_count!=0)poll_count<=poll_count-1'b1;
   case(state)
    BOOT:if(wait_count!=0)wait_count<=wait_count-1'b1;else state<=WRITE;
    WRITE:if(!busy)begin
     address<={8'd0,config_address(config_index)};write_byte<=config_value(config_index);
     reading<=0;start<=1;state<=WRITE_WAIT;
    end
    WRITE_WAIT:if(done)begin if(error)reconnect();else state<=VERIFY;end
    VERIFY:if(!busy)begin reading<=1;start<=1;state<=VERIFY_WAIT;end
    VERIFY_WAIT:if(done)begin
     if(error || data[7:0]!=config_value(config_index))reconnect();
     else if(config_index==24)begin fault<=0;failures<=0;poll_count<=0;state<=IDLE;end
     else begin config_index<=config_index+1'b1;state<=WRITE;end
    end
    IDLE:if(poll_count==0 || (previous_int && !int_sync[1]))begin
     byte_index<=0;retries<=0;poll_count<=POLL_CYCLES-1;state<=READ;
    end
    READ:if(!busy)begin
     address<=byte_index[0]?16'h35:16'h34;reading<=1;start<=1;state<=READ_WAIT;
    end
    READ_WAIT:if(done)begin
     if(error)bad_poll();
     else begin
      case(byte_index)
       0:first_pair[7:0]<=data[7:0];
       1:first_pair[15:8]<=data[7:0];
       2:second_low<=data[7:0];
       3:begin
        if({data[7:0],second_low}==first_pair)begin
         keys<=first_pair;online<=1;report<=1;failures<=0;state<=IDLE;
        end else if(retries==2)bad_poll();
        else begin retries<=retries+1'b1;byte_index<=0;state<=READ;end
       end
      endcase
      if(byte_index!=3)begin byte_index<=byte_index+1'b1;state<=READ;end
     end
    end
    default:reconnect();
   endcase
  end
 end
 // synthesis translate_off
 initial if(BOOT_CYCLES<1 || POLL_CYCLES<1 || RETRY_CYCLES<1)$fatal(1,"Invalid touch keyboard timing");
 // synthesis translate_on
endmodule
