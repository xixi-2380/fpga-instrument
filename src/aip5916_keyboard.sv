`timescale 1ns/1ps
// Independent AiP5916 bus. Communication health and coherent data are separate.
module aip5916_keyboard #(
 parameter integer BOOT_CYCLES=500000,POLL_CYCLES=150000,
 I2C_HALF_CYCLES=250,TIMEOUT_CYCLES=50000,RETRY_CYCLES=500000,
 CLOCK_HZ=50000000,STALE_CYCLES=CLOCK_HZ/20)(
 input wire clk,rst,intr_n,inout wire scl,sda,
 output reg [15:0] keys,output reg online,output reg report,output reg fault,
 input wire cfg_valid,input wire [131:0] cfg_data,output wire cfg_ready,
 output reg cfg_done,output reg [7:0] cfg_error,output reg data_valid,
 output reg [131:0] applied_config,observed_config,
 output wire [639:0] diagnostic,input wire clear_stats);
 localparam BOOT=0,WRITE=1,WRITE_WAIT=2,VERIFY=3,VERIFY_WAIT=4,
 IDLE=5,READ=6,READ_WAIT=7;
 localparam integer MAX_WAIT=BOOT_CYCLES>RETRY_CYCLES?BOOT_CYCLES:RETRY_CYCLES;
 localparam integer BW=MAX_WAIT>1?$clog2(MAX_WAIT):1;
 localparam integer PW=POLL_CYCLES>1?$clog2(POLL_CYCLES):1;
 localparam integer SW=STALE_CYCLES>1?$clog2(STALE_CYCLES+1):1;
 localparam [131:0] DEFAULT_CONFIG={{16{8'h04}},4'h2};
 reg [3:0] state;
 reg [BW-1:0] wait_count;reg [PW-1:0] poll_count;reg [SW-1:0] age;
 reg [4:0] config_index;reg [1:0] byte_index,retries,failures;
 reg [15:0] first_pair,second_pair,candidate;reg [7:0] second_low;
 reg ever_configured;reg [16:0] verified;reg [131:0] working_config;reg applying,configured,sample_seen;
 reg start,reading;reg [15:0] address;reg [7:0] write_byte;
 wire scl_low,sda_low,busy,done,error;wire [71:0] data;wire [63:0] bus_diag;wire [7:0] bus_error;
 reg [15:0] good_count,change_count,nack_count,timeout_count,reinit_count,stale_count;
 reg [7:0] last_reason,last_address,last_expected,last_actual;
 localparam integer MW=$clog2(CLOCK_HZ/1000);
 reg [MW-1:0] millisecond_count;reg [31:0] clocks,last_good_clock;reg [255:0] history;
 (* async_reg="true",syn_async_reg=1 *) reg [1:0] int_sync;
 reg previous_int;
 function automatic [15:0] inc(input [15:0] v);inc=v==16'hffff ? v : v+1'b1;endfunction
 task event_log(input [7:0] reason);
  begin history<={history[223:0],clocks[15:0],reason,address[7:0]};end
 endtask
 always @(posedge clk or posedge rst)
  if(rst)begin int_sync<=3;previous_int<=1;end
  else begin int_sync<={int_sync[0],intr_n};previous_int<=int_sync[1];end
 assign scl=scl_low?1'b0:1'bz;assign sda=sda_low?1'b0:1'bz;
 assign cfg_ready=state==IDLE && !applying;
 i2c_register_master #(.HALF_CYCLES(I2C_HALF_CYCLES),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),
  .REGISTER_BYTES(1),.DEVICE_ADDR(7'h56)) bus(
  clk,rst,start,reading,address,write_byte,4'd1,scl,sda,scl_low,sda_low,busy,done,error,data,bus_diag,bus_error);
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
   4:config_value={4'd0,working_config[3:0]};21:config_value=8'h20;23:config_value=8'h10;
   default:config_value=working_config[4+(n-5)*8+:8];
  endcase end
 endfunction
 task reconnect(input [7:0] reason);
  begin
   keys<=0;candidate<=0;sample_seen<=0;data_valid<=0;online<=0;fault<=1;report<=1;configured<=0;config_index<=0;
   wait_count<=RETRY_CYCLES-1;state<=BOOT;failures<=0;age<=0;
   verified<=0;working_config<=applied_config;reinit_count<=inc(reinit_count);last_reason<=reason;event_log(reason);
   if(applying)begin cfg_done<=1;cfg_error<=reason;applying<=0;end
  end
 endtask
 task bad_poll;
  begin
   candidate<=keys; // failed rounds cannot qualify a key transition
   last_reason<=bus_error==1?8'h11:8'h12;last_address<=address[7:0];last_expected<=0;last_actual<=0;
   event_log(bus_error==1?8'h11:8'h12);
   if(failures==2)reconnect(bus_error==1?8'h11:8'h12);
   else begin failures<=failures+1'b1;state<=IDLE;end
  end
 endtask
 // Fixed diagnostic words; history entries are {milliseconds_low16,reason,register}.
 assign diagnostic={30'd0,ever_configured,verified,history,
  last_good_clock,clocks,
  stale_count,reinit_count,timeout_count,nack_count,change_count,good_count,
  last_reason,last_address,last_expected,last_actual,
  1'b0,configured,applying,data_valid,online,fault,failures,config_index,byte_index,int_sync[1],
  candidate,keys,second_pair,first_pair,bus_diag};
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=BOOT;wait_count<=BOOT_CYCLES-1;poll_count<=0;config_index<=0;
   byte_index<=0;retries<=0;failures<=0;first_pair<=0;second_pair<=0;second_low<=0;candidate<=0;
   start<=0;reading<=0;address<=0;write_byte<=0;keys<=0;online<=0;report<=0;fault<=0;
   ever_configured<=0;verified<=0;sample_seen<=0;applying<=0;configured<=0;working_config<=DEFAULT_CONFIG;applied_config<=DEFAULT_CONFIG;observed_config<=0;
   cfg_done<=0;cfg_error<=0;data_valid<=0;age<=0;millisecond_count<=0;clocks<=0;last_good_clock<=0;history<=0;
   good_count<=0;change_count<=0;nack_count<=0;timeout_count<=0;reinit_count<=0;stale_count<=0;
   last_reason<=0;last_address<=0;last_expected<=0;last_actual<=0;
  end else begin
   start<=0;report<=0;cfg_done<=0;
   if(millisecond_count==CLOCK_HZ/1000-1)begin millisecond_count<=0;clocks<=clocks+1'b1;end
   else millisecond_count<=millisecond_count+1'b1;
   if(clear_stats===1'b1)begin
    good_count<=0;change_count<=0;nack_count<=0;timeout_count<=0;reinit_count<=0;stale_count<=0;history<=0;
    if(!fault && data_valid)begin last_reason<=0;last_address<=0;last_expected<=0;last_actual<=0;end
   end
   // Count transport errors in configuration as well as key polling.
   if(clear_stats!==1'b1 && done && error)begin
    if(bus_error==1)nack_count<=inc(nack_count);else timeout_count<=inc(timeout_count);
   end
   if(poll_count!=0)poll_count<=poll_count-1'b1;
   if(configured && age<STALE_CYCLES)age<=age+1'b1;
   if(configured && age==STALE_CYCLES-1 && data_valid)begin
    sample_seen<=0;data_valid<=0;keys<=0;candidate<=0;report<=1;stale_count<=inc(stale_count);last_reason<=8'h14;last_address<=8'h34;last_expected<=0;last_actual<=0;event_log(8'h14);
   end
   case(state)
    BOOT:if(wait_count!=0)wait_count<=wait_count-1'b1;else state<=WRITE;
    WRITE:if(!busy)begin
     address<={8'd0,config_address(config_index)};write_byte<=config_value(config_index);
     reading<=0;start<=1;state<=WRITE_WAIT;
    end
    WRITE_WAIT:if(done)begin
     if(error)begin last_address<=address[7:0];last_expected<=write_byte;last_actual<=0;reconnect(8'h21);end
     else state<=VERIFY;
    end
    VERIFY:if(!busy)begin reading<=1;start<=1;state<=VERIFY_WAIT;end
    VERIFY_WAIT:if(done)begin
     if(error || data[7:0]!=write_byte)begin
      last_address<=address[7:0];last_expected<=write_byte;last_actual<=error?8'd0:data[7:0];
      reconnect(error?8'h22:8'h23);
     end
     else begin
      if(config_index==4)begin observed_config[3:0]<=data[3:0];verified[0]<=1;end
      // Constant byte destinations avoid a variable write barrel network.
      for(integer channel=0;channel<16;channel=channel+1)if(config_index==channel+5)begin
       observed_config[4+channel*8+:8]<=data[7:0];verified[channel+1]<=1;
      end
      if(config_index==24)begin
       fault<=0;failures<=0;poll_count<=0;state<=IDLE;configured<=1;ever_configured<=1;online<=1;age<=0;
       if(applying)begin applied_config<=working_config;cfg_done<=1;cfg_error<=0;applying<=0;end
      end else begin config_index<=config_index+1'b1;state<=WRITE;end
     end
    end
    IDLE:if(cfg_valid===1'b1)begin
     working_config<=cfg_data;verified<=0;sample_seen<=0;applying<=1;cfg_error<=0;configured<=0;data_valid<=0;
     keys<=0;candidate<=0;report<=1;config_index<=0;state<=WRITE;
    end else if(poll_count==0 || (previous_int && !int_sync[1]))begin
     byte_index<=0;retries<=0;poll_count<=POLL_CYCLES-1;state<=READ;
    end
    READ:if(!busy)begin address<=byte_index[0]?16'h35:16'h34;reading<=1;start<=1;state<=READ_WAIT;end
    READ_WAIT:if(done)begin
     if(error)bad_poll();
     else begin
      case(byte_index)
       0:first_pair[7:0]<=data[7:0];1:first_pair[15:8]<=data[7:0];2:second_low<=data[7:0];
       3:begin
        second_pair<={data[7:0],second_low};failures<=0;
        if({data[7:0],second_low}==first_pair)begin
         // Each bit needs two consecutive coherent samples. Stale recovery
         // presents an invalid qualification first, then the real key bitmap.
         for(integer k=0;k<16;k++)if(first_pair[k]==candidate[k])keys[k]<=first_pair[k];
         candidate<=first_pair;data_valid<=sample_seen;sample_seen<=1;online<=1;report<=1;age<=0;
         good_count<=inc(good_count);last_good_clock<=clocks;state<=IDLE;
        end else begin
         change_count<=inc(change_count);event_log(8'h13);candidate<=keys;
         if(retries==2)state<=IDLE;
         else begin retries<=retries+1'b1;byte_index<=0;state<=READ;end
        end
       end
      endcase
      if(byte_index!=3)begin byte_index<=byte_index+1'b1;state<=READ;end
     end
    end
    default:reconnect(8'h2f);
   endcase
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(!rst && state==VERIFY_WAIT && done && write_byte!==config_value(config_index))
  $fatal(1,"Configuration changed between write and readback verification");
 initial if(BOOT_CYCLES<1 || POLL_CYCLES<1 || RETRY_CYCLES<1 || STALE_CYCLES<2)$fatal(1,"Invalid touch timing");
 // synthesis translate_on
endmodule
