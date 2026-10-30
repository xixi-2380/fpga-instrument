`timescale 1ns/1ps
// Audio-domain performance control. Recorder never backpressures the synth.
// Map bytes are {timbre(31=global), MIDI pitch}; capture words are independent
// from the score's 12-byte wire format (32-bit duration here).
module instrument_features #(parameter integer MS_CYCLES=61440,MAX_NOTES=4096,MAX_MS=3600000)(
 input wire clk,rst,request_valid,output wire request_ready,input wire [80:0] request,
 output wire response_valid,input wire response_ready,output reg [164:0] response,
 input wire unavailable,input wire [35:0] keys,input wire key_pending,
 input wire event_valid,event_on,input wire [5:0] event_key,input wire [6:0] event_pitch,event_velocity,input wire [4:0] event_timbre,
 input wire local_start,local_stop,output reg [7:0] local_error,
 output reg [575:0] keymap,output wire performance_lock,output wire [63:0] ui_status,
 input wire load_valid,output wire load_ready,input wire [575:0] load_map,
 output wire save_valid,input wire save_ready,output wire [591:0] save_data,input wire [31:0] save_status,input wire local_cancel);
 localparam IDLE=0,REPLY=1,MAP_CRC=2,SAVE=3,READ_WAIT=4,READ_REPLY=5;
 reg [2:0] state;reg [575:0] stage;reg [35:0] stage_mask;reg [31:0] stage_token,stage_crc,map_crc,saved_crc;
 reg local_confirm;reg loading;reg stage_open;reg [15:0] map_version,save_id;reg [6:0] map_byte;reg [31:0] map_check;
 reg [95:0] memory[0:MAX_NOTES-1] /* synthesis syn_ramstyle = "block_ram" */;reg [95:0] read_word;
 reg [11:0] read_index;reg [12:0] count;reg [31:0] capture_id,elapsed,final_crc;
 reg [2:0] rec_state; // 0 empty,1 recording,2 close,3 crc fetch,4 crc byte,5 frozen
 reg [7:0] reason;reg [35:0] held;reg [11:0] slots[0:35];reg [31:0] starts[0:35];reg [31:0] meta[0:35];
 reg [5:0] close_key;reg [12:0] crc_index;reg [3:0] crc_byte;reg [31:0] crc;
 localparam MW=MS_CYCLES>1?$clog2(MS_CYCLES):1;
 reg [MW-1:0] ms_count;
 wire [7:0] cmd=request[7:0];wire [8:0] len=request[16:8];wire [63:0] data=request[80:17];
 wire map_idle=keys==0 && !key_pending && !unavailable && !performance_lock;
 assign request_ready=state==IDLE && !load_valid;
 assign response_valid=state==REPLY;
 assign performance_lock=rec_state>=1 && rec_state<=4;
 assign load_ready=state==IDLE && !performance_lock && (map_version==0 || (keys==0 && !key_pending));
 assign save_valid=state==SAVE;assign save_data={save_id,keymap};
 assign ui_status={local_confirm,capture_id[14:0],elapsed[19:0],count,local_error,reason[3:0],rec_state};
 function automatic [31:0] crc8(input [31:0] c,input [7:0] b);
 reg [31:0] v;begin v=c^{24'd0,b};for(integer j=0;j<8;j++)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc8=v;end endfunction
 function automatic [575:0] defaults;
 begin for(integer j=0;j<36;j++)begin defaults[j*16+:8]=60+j;defaults[j*16+8+:8]=31;end end endfunction
 function automatic [31:0] config_crc(input [575:0] m);
 reg [31:0] c;begin c=32'hffffffff;for(integer j=0;j<72;j++)c=crc8(c,m[j*8+:8]);config_crc=~c;end endfunction
 task automatic answer(input [7:0] error,input [4:0] n);
 begin response<=0;response[7:0]<=error;response[164:160]<=error==0?n:5'd1;state<=REPLY;end endtask
 task automatic begin_capture;
 begin local_confirm<=0;local_error<=0;capture_id<=capture_id+1'b1;count<=0;elapsed<=0;ms_count<=0;held<=0;reason<=0;final_crc<=0;rec_state<=1;end endtask
 task automatic close_capture(input [7:0] why);
 begin reason<=why;close_key<=0;rec_state<=2;end endtask
 // One synchronous read port and one synchronous write port. Keep all RAM
 // access out of the asynchronous-reset controller: resetting controller state
 // invalidates old records via count/held, without resetting the RAM array.
 wire memory_read_enable=(rec_state==3 && crc_index<count) || state==READ_WAIT;
 wire [11:0] memory_read_address=rec_state==3 ? crc_index[11:0] : read_index;
 reg memory_write_enable;reg [11:0] memory_write_address;reg [95:0] memory_write_data;
 always @*begin
  memory_write_enable=0;memory_write_address=0;memory_write_data=0;
  if(!rst)begin
   if(rec_state==1 && event_valid && event_key<36)begin
    if(event_on && !held[event_key] && count<MAX_NOTES)begin
     memory_write_enable=1;memory_write_address=count[11:0];
     memory_write_data={{2'd0,event_key},{3'd0,event_timbre},{1'b0,event_velocity},{1'b0,event_pitch},32'd0,elapsed};
    end else if(!event_on && held[event_key])begin
     memory_write_enable=1;memory_write_address=slots[event_key];
     memory_write_data={meta[event_key],(elapsed>starts[event_key]?elapsed-starts[event_key]:32'd1),starts[event_key]};
    end
   end else if(rec_state==2 && held[close_key])begin
    memory_write_enable=1;memory_write_address=slots[close_key];
    memory_write_data={meta[close_key],(elapsed>starts[close_key]?elapsed-starts[close_key]:32'd1),starts[close_key]};
   end
  end
 end
 always @(posedge clk)begin
  if(memory_write_enable)memory[memory_write_address]<=memory_write_data;
  if(memory_read_enable)read_word<=memory[memory_read_address];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   keymap<=defaults();map_crc<=config_crc(defaults());map_version<=0;stage<=0;stage_mask<=0;stage_open<=0;loading<=0;stage_token<=0;stage_crc<=0;
   saved_crc<=0;map_byte<=0;map_check<=0;state<=IDLE;response<=0;save_id<=0;read_index<=0;
   local_confirm<=0;rec_state<=0;count<=0;capture_id<=0;elapsed<=0;ms_count<=0;held<=0;reason<=0;local_error<=0;final_crc<=0;close_key<=0;crc_index<=0;crc_byte<=0;crc<=0;
  end else begin
   if(load_valid && load_ready)begin keymap<=load_map;stage<=load_map;loading<=1;map_byte<=0;map_check<=32'hffffffff;state<=MAP_CRC;map_version<=map_version+1'b1;end
   // Accepted manual events only. Release words are rebuilt from onset context,
   // so later timbre selections cannot rewrite the recorded onset.
   if(rec_state==1)begin
    if(ms_count==MS_CYCLES-1)begin ms_count<=0;elapsed<=elapsed+1'b1;end else ms_count<=ms_count+1'b1;
    if(event_valid && event_key<36)begin
     if(event_on && !held[event_key])begin
      if(count<MAX_NOTES)begin
       slots[event_key]<=count[11:0];starts[event_key]<=elapsed;
       meta[event_key]<={{2'd0,event_key},{3'd0,event_timbre},{1'b0,event_velocity},{1'b0,event_pitch}};
       held[event_key]<=1;count<=count+1'b1;
       if(count==MAX_NOTES-1)close_capture(2);
      end else close_capture(2);
     end else if(!event_on && held[event_key])begin
      held[event_key]<=0;
     end
    end
    if(elapsed>=MAX_MS-1 && ms_count==MS_CYCLES-1)close_capture(3);
    if(unavailable)close_capture(4);
   end else if(rec_state==2)begin
    if(held[close_key])held[close_key]<=0;
    if(close_key==35)begin crc<=32'hffffffff;crc_index<=0;rec_state<=3;end else close_key<=close_key+1'b1;
   end else if(rec_state==3)begin
    if(crc_index==count)begin final_crc<=~crc;rec_state<=5;end
    else begin crc_byte<=0;rec_state<=4;end
   end else if(rec_state==4)begin
    crc<=crc8(crc,read_word[crc_byte*8+:8]);
    if(crc_byte==11)begin crc_index<=crc_index+1'b1;rec_state<=3;end else crc_byte<=crc_byte+1'b1;
   end
   if(local_cancel===1'b1 || local_stop || (request_valid && request_ready))local_confirm<=0;
   if(local_start)begin
    if(state==IDLE && map_idle && save_status[28])begin
     if(rec_state==5 && count!=0 && !local_confirm)begin local_confirm<=1;local_error<=0;end
     else begin begin_capture();local_error<=0;end
    end else local_error<=5;
   end
   if(local_stop)begin if(rec_state==1)begin close_capture(1);local_error<=0;end else if(rec_state!=2 && rec_state!=3 && rec_state!=4)local_error<=5;end
   case(state)
    IDLE:if(request_valid && request_ready)begin
     case(cmd)
      8'h50:if(len!=0)answer(3,1);else begin answer(0,12);response[15:8]<=1;response[23:16]<=36;response[31:24]<=21;response[39:32]<=108;response[47:40]<=16;response[63:48]<=MAX_NOTES;response[95:64]<=MAX_MS;end
      8'h51:if(len!=1)answer(3,1);else if(data[7:0]>=36)answer(6,1);else begin answer(0,4);response[15:8]<=data[7:0];response[31:16]<=keymap[data[7:0]*16+:16];end
      8'h52:if(len!=8)answer(3,1);else if(performance_lock || state==SAVE)answer(5,1);else begin stage_token<=data[31:0];stage_crc<=data[63:32];stage_mask<=0;stage_open<=1;answer(0,1);end
      8'h53:if(len!=7)answer(3,1);else if(!stage_open || data[31:0]!=stage_token || data[39:32]>=36 || data[47:40]<21 || data[47:40]>108 || (data[55:48]>15 && data[55:48]!=31))answer(6,1);
       else begin stage[data[39:32]*16+:16]<=data[55:40];stage_mask[data[39:32]]<=1;answer(0,1);end
      8'h54:if(len!=4)answer(3,1);else if(!stage_open || data[31:0]!=stage_token || !(&stage_mask))answer(6,1);else if(!map_idle || !save_status[28])answer(5,1);else begin map_byte<=0;map_check<=32'hffffffff;state<=MAP_CRC;end
      8'h55:if(len!=4)answer(3,1);else if(!map_idle || !save_status[28] || save_status[17:16]==1)answer(5,1);else if(!save_status[29])answer(8'h21,1);else if(data[31:0]!=map_crc)answer(6,1);else begin saved_crc<=map_crc;save_id<=save_id+1'b1;state<=SAVE;end
      8'h56:if(len!=0)answer(3,1);else begin answer(0,16);response[23:8]<=save_status[15:0];response[31:24]<={6'd0,save_status[17:16]};response[39:32]<=save_status[25:18];response[71:40]<=saved_crc;response[79:72]<={4'd0,save_status[29:26]};response[95:80]<=map_version;response[127:96]<=map_crc;end
      8'h57:if(len!=0)answer(3,1);else if(!map_idle || !save_status[28])answer(5,1);else begin keymap<=defaults();map_crc<=config_crc(defaults());map_version<=map_version+1'b1;answer(0,1);end
      8'h60,8'h63:if(len!=0)answer(3,1);else begin answer(0,20);response[15:8]<={5'd0,rec_state};response[47:16]<=capture_id;response[63:48]<={3'd0,count};response[95:64]<=elapsed;response[127:96]<=final_crc;response[135:128]<=reason;response[143:136]<=local_error;end
      8'h61:if(len!=0)answer(3,1);else if(!map_idle || !save_status[28] || save_status[17:16]==1)answer(5,1);else begin begin_capture();answer(0,5);response[39:8]<=capture_id+1'b1;end
      8'h62:if(len!=0)answer(3,1);else if(rec_state!=1 && rec_state!=2 && rec_state!=3 && rec_state!=4 && rec_state!=5)answer(5,1);else begin if(rec_state==1)close_capture(1);answer(0,1);end
      8'h64:if(len!=6)answer(3,1);else if(rec_state!=5)answer(5,1);else if(data[31:0]!=capture_id || data[47:32]>=count)answer(6,1);else begin read_index<=data[43:32];state<=READ_WAIT;end
      8'h65:if(len!=4)answer(3,1);else if(performance_lock)answer(5,1);else if(data[31:0]!=capture_id)answer(6,1);else begin rec_state<=0;count<=0;final_crc<=0;reason<=0;answer(0,1);end
      8'h66:if(len!=0)answer(3,1);else begin answer(0,8);response[15:8]<=1;response[31:16]<=MAX_NOTES;response[63:32]<=MAX_MS;end
      default:answer(1,1);
     endcase
    end
    MAP_CRC:if(map_byte==72)begin
     if(loading)begin map_crc<=~map_check;loading<=0;state<=IDLE;end
     else if((~map_check)!=stage_crc)answer(9,1);
     else if(!map_idle)answer(5,1);
     else begin keymap<=stage;map_crc<=stage_crc;map_version<=map_version+1'b1;stage_open<=0;answer(0,1);end
    end else begin map_check<=crc8(map_check,stage[map_byte*8+:8]);map_byte<=map_byte+1'b1;end
    SAVE:if(save_ready)begin answer(0,3);response[23:8]<=save_id;end
    READ_WAIT:state<=READ_REPLY;
    READ_REPLY:begin answer(0,20);response[39:8]<=capture_id;response[55:40]<={4'd0,read_index};response[63:56]<=1;response[159:64]<=read_word;end
    REPLY:if(response_ready)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
