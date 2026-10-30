`timescale 1ns/1ps
// Dual independent sectors outside all existing song slots. Commit is written
// only after body readback. Boot scan never modifies Flash.
module flash_keymap(
 input wire clk,rst,initialized,supported,writable,input wire [23:0] jedec,
 input wire save_valid,output wire save_ready,input wire [591:0] save_data,
 output wire load_valid,input wire load_ready,output reg [575:0] load_map,output wire [31:0] status,
 output wire busy,output wire flash_valid,input wire flash_ready,output wire [1:0] flash_op,
 output wire [23:0] flash_address,output wire [8:0] flash_length,input wire flash_done,input wire [7:0] flash_error,
 output wire buffer_write,output wire [7:0] buffer_index,buffer_wdata,read_index,input wire [7:0] read_data);
 localparam BOOT=0,READ=1,WAIT=2,ADDR=3,DELAY=4,BYTE=5,CHECK=6,LOAD=7,IDLE=8,
 BUILD=9,ERASE=10,FILL=11,PROGRAM=12,VERIFY=13,COMMIT_FILL=14,COMMIT=15,FINISH=16;
 reg [4:0] state,next_state;reg slot,active,have_active,boot_scan,verify_commit;
 reg [31:0] generation,chosen_generation;reg [15:0] job_id;reg [1:0] job_state,boot_status;reg [7:0] error;
 reg [703:0] page,image;reg [6:0] index;reg [31:0] crc;
 wire capacity=supported && jedec[7:0]>=8'h16 && jedec[7:0]<=8'h18;
 wire valid_map;
 reg map_legal;
 always @*begin map_legal=1;for(integer j=0;j<36;j++)if(page[64+j*16+:8]<21 || page[64+j*16+:8]>108 || (page[72+j*16+:8]>15 && page[72+j*16+:8]!=31))map_legal=0;end
 assign valid_map=page[31:0]==32'h50414d4b && page[703:672]==32'h454e4f44 && page[671:640]==~crc && map_legal;
 assign busy=state!=IDLE;
 assign save_ready=state==IDLE && capacity && writable;
 assign load_valid=state==LOAD;
 assign status={2'd0,(capacity && writable),(state==IDLE),boot_status,error,job_state,job_id};
 assign flash_valid=state==READ || state==ERASE || state==PROGRAM || state==COMMIT;
 assign flash_op=state==ERASE?2'd3:state==PROGRAM || state==COMMIT?2'd2:2'd1;
 assign flash_address=(slot?24'h221000:24'h220000)+(state==COMMIT?24'd84:24'd0);
 assign flash_length=state==ERASE?9'd1:state==COMMIT?9'd4:state==PROGRAM?9'd84:9'd88;
 assign buffer_write=state==FILL || state==COMMIT_FILL;
 assign buffer_index=state==COMMIT_FILL?{6'd0,index[1:0]}:{1'd0,index};
 assign buffer_wdata=state==COMMIT_FILL?(32'h454e4f44>>(index*8)):image[index*8+:8];
 assign read_index={1'd0,index};
 function automatic [31:0] crc8(input [31:0] c,input [7:0] b);
 reg [31:0] v;begin v=c^{24'd0,b};for(integer j=0;j<8;j++)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc8=v;end endfunction
 function automatic [575:0] defaults;
 begin for(integer j=0;j<36;j++)begin defaults[j*16+:8]=60+j;defaults[j*16+8+:8]=31;end end endfunction
 task automatic failed(input [7:0] code);
 begin error<=code;job_state<=3;state<=IDLE;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=BOOT;next_state<=0;slot<=0;active<=0;have_active<=0;boot_scan<=1;verify_commit<=0;generation<=0;chosen_generation<=0;job_id<=0;job_state<=0;error<=0;boot_status<=0;page<=0;image<=0;index<=0;crc<=0;load_map<=defaults();end
  else case(state)
   BOOT:if(initialized)begin if(!capacity)begin boot_status<=3;state<=LOAD;end else state<=READ;end
   READ:if(flash_ready)begin next_state<=ADDR;state<=WAIT;index<=0;crc<=32'hffffffff;end
   WAIT:if(flash_done)begin
    if(flash_error!=0)begin
     if(boot_scan)begin boot_status<=3;error<=flash_error;state<=LOAD;end else failed(flash_error);
    end else state<=next_state;
   end
   ADDR:state<=DELAY;
   DELAY:state<=BYTE;
   BYTE:begin
    page[index*8+:8]<=read_data;if(index<80)crc<=crc8(crc,read_data);
    if(index==87)state<=CHECK;else begin index<=index+1'b1;state<=ADDR;end
   end
   CHECK:if(boot_scan)begin
    if(valid_map && (!have_active || $signed(page[63:32]-chosen_generation)>0))begin load_map<=page[639:64];chosen_generation<=page[63:32];active<=slot;have_active<=1;boot_status<=1;end
    else if(!valid_map && page!={704{1'b1}} && !have_active)boot_status<=2;
    if(!slot)begin slot<=1;state<=READ;end else state<=LOAD;
   end else if(!verify_commit)begin
    if(page[671:0]!=image[671:0])failed(9);else begin index<=0;state<=COMMIT_FILL;end
   end else if(page!=image)failed(9);
    else begin have_active<=1;active<=slot;chosen_generation<=generation;boot_status<=1;job_state<=2;error<=0;state<=IDLE;end
   LOAD:if(load_ready)begin boot_scan<=0;state<=IDLE;end
   IDLE:if(save_valid && save_ready)begin
    job_id<=save_data[591:576];job_state<=1;error<=0;slot<=have_active?!active:1'b0;generation<=chosen_generation+1'b1;
    image<={32'h454e4f44,32'd0,save_data[575:0],chosen_generation+32'd1,32'h50414d4b};
    crc<=32'hffffffff;index<=0;state<=BUILD;verify_commit<=0;
   end
   BUILD:if(index==80)begin image[671:640]<=~crc;state<=ERASE;end else begin crc<=crc8(crc,image[index*8+:8]);index<=index+1'b1;end
   ERASE:if(flash_ready)begin next_state<=FILL;index<=0;state<=WAIT;end
   FILL:if(flash_ready)begin if(index==83)state<=PROGRAM;else index<=index+1'b1;end
   PROGRAM:if(flash_ready)begin next_state<=READ;state<=WAIT;end
   COMMIT_FILL:if(flash_ready)begin if(index==3)state<=COMMIT;else index<=index+1'b1;end
   COMMIT:if(flash_ready)begin verify_commit<=1;next_state<=READ;state<=WAIT;end
   default:state<=BOOT;
  endcase
 end
endmodule
