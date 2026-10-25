`timescale 1ns/1ps
// Fixed-slot copy-on-write song library. All interfaces are in the ref domain.
// Two 4KiB directory sectors, 33 x64KiB payload slots for32 entries +1 spare.
module flash_song_library #(parameter integer MAX_NOTES=4096,AW=(MAX_NOTES>1?$clog2(MAX_NOTES):1))(
 input wire clk,rst,request_valid,output wire request_ready,input wire [1:0] command,
 input wire [4:0] song_index,input wire [55:0] song_name,
 output wire busy,output reg initialized,output reg [15:0] job_id,
 output reg [1:0] job_state,output reg [7:0] error,output reg done,
 output reg [31:0] entries,output reg loaded_valid,output reg [4:0] loaded_index,
 input wire [4:0] lookup_index,output reg [159:0] lookup_data,
 input wire ram_valid,input wire [15:0] ram_count,input wire [31:0] ram_duration,ram_crc,
 output wire storage_lock,input wire storage_ready,output reg storage_write,storage_invalidate,
 output reg [AW-1:0] storage_address,output reg [63:0] storage_wdata,input wire [63:0] storage_rdata,
 output wire storage_import,output reg [15:0] storage_count,output reg [31:0] storage_crc,
 input wire storage_done,input wire [7:0] storage_error,input wire upload_active,
 input wire flash_initialized,flash_supported,flash_ready,
 output wire flash_valid,output reg [1:0] flash_op,output reg [23:0] flash_address,output reg [8:0] flash_length,
 input wire flash_done,input wire [7:0] flash_error,
 output reg buffer_write,output reg [7:0] buffer_index,buffer_wdata,
 output reg [7:0] read_index,input wire [7:0] read_data);
 localparam integer DIR_BYTES=1056;
 localparam [6:0] BOOT=0,READY=1,JOB_START=2,LOOKUP_WAIT=3,LOOKUP_LATCH=4,
 ALLOC_START=5,ALLOC_READ=6,ALLOC_WAIT=7,ALLOC_SLOT=8,ERASE_DATA=9,ERASE_NEXT=10,
 SAVE_WORD=11,SAVE_WAIT=12,SAVE_LATCH=13,SAVE_BYTE=14,PROGRAM_PAGE=15,READ_PAYLOAD=16,
 PAYLOAD_FETCH=17,PAYLOAD_WAIT=18,PAYLOAD_BYTE=19,PAYLOAD_NEXT=20,LOAD_WRITE=21,IMPORT=22,
 BUILD_HEADER=23,BUILD_META=24,BUILD_META_WAIT=25,BUILD_ENTRY=26,BUILD_CRC=27,DIR_ERASE=28,
 DIR_FILL=29,DIR_FILL_WAIT=30,DIR_FILL_BYTE=31,DIR_PROGRAM=32,DIR_WRITE_NEXT=33,
 DIR_READ=34,DIR_FETCH=35,DIR_WAIT=36,DIR_BYTE=37,DIR_NEXT=38,DIR_CHECK=39,
 APPLY=40,BOOT_NEXT=41,MARK_FILL=42,MARK_PROGRAM=43,MARK_READ=44,MARK_FETCH=45,MARK_WAIT=46,MARK_CHECK=47,
 FINISH=48,IO_SEND=49,IO_WAIT=50;
 reg [6:0] state,io_return;reg [1:0] operation;reg [4:0] target;
 reg [159:0] catalog[0:31],candidates[0:31],catalog_read,meta_shift,new_meta;
 reg [7:0] directory[0:DIR_BYTES-1],directory_data;
 reg [4:0] meta_index;reg [5:0] meta_byte;reg [10:0] offset;
 reg [31:0] generation,candidate_generation,crc,stored_crc,magic,marker;
 reg [31:0] candidate_entries;reg [32:0] used_slots;reg [5:0] slot;
 reg active_bank,have_directory,scan_bank,verify_directory,boot_failed,bad_directory,bank_nonblank,any_nonblank;
 reg [7:0] format,entry_limit;reg [15:0] record_no;reg [63:0] word_shift;
 reg [15:0] payload_bytes;reg [7:0] page;reg [3:0] sector;reg [8:0] byte_no,page_length;
 reg [23:0] payload_base,dir_base;reg [7:0] commit_index;
 reg [31:0] expected_duration;
 wire [4:0] catalog_address=state==READY ? lookup_index : meta_index;
 wire [31:0] crc_next=crc_byte(crc,read_data);
 wire [159:0] parsed_meta={read_data,meta_shift[159:8]};
 wire skip_crc=(offset>=12 && offset<20);
 wire [23:0] current_page=payload_base+{8'd0,page,8'd0};
 assign request_ready=state==READY && initialized && !rst;
 assign busy=state!=READY;
 assign storage_lock=state!=READY && initialized;
 assign storage_import=state==IMPORT;
 assign flash_valid=state==IO_SEND;
 function automatic [31:0] crc_byte(input [31:0] c,input [7:0] b);
 reg [31:0] x;begin x=c^{24'd0,b};for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);crc_byte=x;end endfunction
 function automatic [7:0] header_byte(input [4:0] n,input [31:0] gen);
 begin case(n)
  0:header_byte="F";1:header_byte="S";2:header_byte="C";3:header_byte="1";
  4:header_byte=1;5:header_byte=32;
  8:header_byte=gen[7:0];9:header_byte=gen[15:8];10:header_byte=gen[23:16];11:header_byte=gen[31:24];
  16,17,18,19:header_byte=255;default:header_byte=0;
 endcase end endfunction
 function automatic [7:0] marker_byte(input [1:0] n);
 begin case(n)0:marker_byte="D";1:marker_byte="O";2:marker_byte="N";3:marker_byte="E";endcase end endfunction
 function automatic [55:0] default_name(input [4:0] id);
 begin default_name={8'd0,8'd0,8'd0,8'(48+((id+1)%10)),8'(48+((id+1)/10)),8'd48,8'd83};end endfunction
 task automatic io(input [1:0] op,input [23:0] addr,input [8:0] len,input [6:0] next_state);
 begin flash_op<=op;flash_address<=addr;flash_length<=len;io_return<=next_state;state<=IO_SEND;end endtask
 task automatic finish(input [7:0] e);begin error<=e;job_state<=e==0?2:3;state<=FINISH;end endtask
 task automatic start_directory_read;
 begin offset<=0;page<=0;crc<=32'hffffffff;stored_crc<=0;magic<=0;marker<=0;candidate_generation<=0;
  candidate_entries<=0;bad_directory<=0;bank_nonblank<=0;used_slots<=0;state<=DIR_READ;end endtask
 always @(posedge clk)begin
  catalog_read<=catalog[catalog_address];lookup_data<=entries[lookup_index]?catalog[lookup_index]:160'd0;
  directory_data<=directory[offset];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=BOOT;io_return<=READY;operation<=0;target<=0;initialized<=0;job_id<=0;job_state<=0;error<=0;done<=0;
   entries<=0;loaded_valid<=0;loaded_index<=0;storage_write<=0;storage_invalidate<=0;storage_address<=0;storage_wdata<=0;storage_count<=0;storage_crc<=0;
   flash_op<=0;flash_address<=0;flash_length<=0;buffer_write<=0;buffer_index<=0;buffer_wdata<=0;read_index<=0;
   meta_shift<=0;new_meta<=0;meta_index<=0;meta_byte<=0;offset<=0;generation<=0;candidate_generation<=0;crc<=0;stored_crc<=0;magic<=0;marker<=0;
   candidate_entries<=0;used_slots<=0;slot<=0;active_bank<=1;have_directory<=0;scan_bank<=0;verify_directory<=0;boot_failed<=0;bad_directory<=0;bank_nonblank<=0;any_nonblank<=0;
   format<=0;entry_limit<=0;record_no<=0;word_shift<=0;payload_bytes<=0;page<=0;sector<=0;byte_no<=0;page_length<=0;payload_base<=0;dir_base<=0;commit_index<=0;expected_duration<=0;
  end else begin
   done<=0;storage_write<=0;storage_invalidate<=0;buffer_write<=0;
   if(upload_active)loaded_valid<=0;
   case(state)
    BOOT:if(flash_initialized && flash_ready)begin dir_base<=0;scan_bank<=0;verify_directory<=0;start_directory_read();end
    READY:if(request_valid)begin
     operation<=command;target<=song_index;meta_index<=song_index;job_id<=job_id+1'b1;job_state<=1;error<=0;
     new_meta<=0;state<=JOB_START;
     if(command==0)begin
      storage_count<=ram_count;storage_crc<=ram_crc;
      new_meta<={8'd0,(song_name==0?default_name(song_index):song_name),ram_crc,ram_duration,ram_count,8'd0,8'd1};
     end
    end
    JOB_START:if(!storage_ready || upload_active)finish(5);
     else if(operation>2)finish(6);
     else if(!flash_supported)finish(8'h21);
     else if(operation==0 && (!ram_valid || storage_count==0 || storage_count>MAX_NOTES))finish(8'h0e);
     else if(operation!=0 && !entries[target])finish(8'h0e);
     else state<=LOOKUP_WAIT;
    LOOKUP_WAIT:state<=LOOKUP_LATCH;
    LOOKUP_LATCH:if(operation==0)begin used_slots<=0;meta_index<=0;state<=ALLOC_READ;end
     else if(operation==2)begin offset<=0;crc<=32'hffffffff;state<=BUILD_HEADER;end
     else begin
      storage_count<=catalog_read[31:16];storage_crc<=catalog_read[95:64];payload_bytes<=catalog_read[31:16]<<3;expected_duration<=catalog_read[63:32];
      payload_base<=24'h010000+{catalog_read[15:8],16'd0};page<=0;record_no<=0;
      storage_invalidate<=1;loaded_valid<=0;crc<=32'hffffffff;state<=READ_PAYLOAD;
     end
    ALLOC_READ:state<=ALLOC_WAIT;
    ALLOC_WAIT:begin
     if(entries[meta_index])used_slots[catalog_read[13:8]]<=1;
     if(meta_index==31)begin slot<=0;state<=ALLOC_SLOT;end else begin meta_index<=meta_index+1'b1;state<=ALLOC_READ;end
    end
    ALLOC_SLOT:if(!used_slots[slot])begin
      new_meta[15:8]<={2'd0,slot};payload_base<=24'h010000+{2'd0,slot,16'd0};payload_bytes<=storage_count<<3;
      sector<=0;page<=0;record_no<=0;crc<=32'hffffffff;state<=ERASE_DATA;
     end else if(slot==32)finish(8);else slot<=slot+1'b1;
    ERASE_DATA:io(3,payload_base+{8'd0,sector,12'd0},1,ERASE_NEXT);
    ERASE_NEXT:if(({12'd0,sector}+1)*4096>=payload_bytes)begin byte_no<=0;state<=SAVE_WORD;end
     else begin sector<=sector+1'b1;state<=ERASE_DATA;end
    SAVE_WORD:begin storage_address<=record_no[AW-1:0];state<=SAVE_WAIT;end
    SAVE_WAIT:state<=SAVE_LATCH;
    SAVE_LATCH:begin word_shift<=storage_rdata;meta_byte<=0;state<=SAVE_BYTE;end
    SAVE_BYTE:begin
     buffer_write<=1;buffer_index<=byte_no[7:0];buffer_wdata<=word_shift[7:0];word_shift<=word_shift>>8;
     byte_no<=byte_no+1'b1;
     if(meta_byte==7)begin
      record_no<=record_no+1'b1;
      if(byte_no==255 || record_no+1==storage_count)begin page_length<=byte_no+1'b1;state<=PROGRAM_PAGE;end
      else state<=SAVE_WORD;
     end else meta_byte<=meta_byte+1'b1;
    end
    PROGRAM_PAGE:io(2,current_page,page_length,READ_PAYLOAD);
    READ_PAYLOAD:begin
     byte_no<=0;read_index<=0;
     if(operation==1)page_length<=((payload_bytes-{page,8'd0})>=256)?9'd256:(payload_bytes-{page,8'd0});
     io(1,current_page,operation==0?page_length:(((payload_bytes-{page,8'd0})>=256)?9'd256:(payload_bytes-{page,8'd0})),PAYLOAD_FETCH);
    end
    PAYLOAD_FETCH:begin read_index<=byte_no[7:0];state<=PAYLOAD_WAIT;end
    PAYLOAD_WAIT:state<=PAYLOAD_BYTE;
    PAYLOAD_BYTE:begin
     crc<=crc_next;word_shift<={read_data,word_shift[63:8]};
     if(operation==1 && byte_no[2:0]==7)begin
      storage_wdata<={read_data,word_shift[63:8]};storage_address<=record_no[AW-1:0];storage_write<=1;
      record_no<=record_no+1'b1;state<=LOAD_WRITE;
     end else state<=PAYLOAD_NEXT;
    end
    LOAD_WRITE:state<=PAYLOAD_NEXT;
    PAYLOAD_NEXT:if(byte_no+1==page_length)begin
     if({page,8'd0}+page_length>=payload_bytes)begin
      if((crc^32'hffffffff)!=storage_crc)finish(9);
      else if(operation==1)state<=IMPORT;
      else begin offset<=0;crc<=32'hffffffff;state<=BUILD_HEADER;end
     end else begin page<=page+1'b1;byte_no<=0;state<=operation==0?SAVE_WORD:READ_PAYLOAD;end
    end else begin byte_no<=byte_no+1'b1;state<=PAYLOAD_FETCH;end
    IMPORT:if(storage_done)begin
     if(storage_error==0 && ram_duration==expected_duration)begin loaded_valid<=1;loaded_index<=target;finish(0);end
     else begin storage_invalidate<=1;finish(storage_error==0?8'd9:storage_error);end
    end
    BUILD_HEADER:begin
     directory[offset]<=header_byte(offset[4:0],generation+1'b1);
     if(!skip_crc)crc<=crc_byte(crc,header_byte(offset[4:0],generation+1'b1));
     if(offset==31)begin meta_index<=0;state<=BUILD_META;end else offset<=offset+1'b1;
    end
    BUILD_META:state<=BUILD_META_WAIT;
    BUILD_META_WAIT:begin
     meta_shift<=meta_index==target ? (operation==2?160'd0:new_meta) : (entries[meta_index]?catalog_read:160'd0);
     meta_byte<=0;state<=BUILD_ENTRY;
    end
    BUILD_ENTRY:begin
     directory[32+{meta_index,5'd0}+meta_byte]<=meta_byte<20?meta_shift[7:0]:8'd0;
     crc<=crc_byte(crc,meta_byte<20?meta_shift[7:0]:8'd0);meta_shift<=meta_shift>>8;
     if(meta_byte==31)begin
      if(meta_index==31)begin commit_index<=0;state<=BUILD_CRC;end
      else begin meta_index<=meta_index+1'b1;state<=BUILD_META;end
     end else meta_byte<=meta_byte+1'b1;
    end
    BUILD_CRC:begin
     directory[12+commit_index]<=~crc[7:0];crc<=crc>>8;
     if(commit_index==3)begin dir_base<=active_bank?24'h000000:24'h001000;state<=DIR_ERASE;end
     else commit_index<=commit_index+1'b1;
    end
    DIR_ERASE:begin offset<=0;page<=0;byte_no<=0;io(3,dir_base,1,DIR_FILL);end
    DIR_FILL:state<=DIR_FILL_WAIT;
    DIR_FILL_WAIT:state<=DIR_FILL_BYTE;
    DIR_FILL_BYTE:begin
     buffer_write<=1;buffer_index<=offset[7:0];buffer_wdata<=directory_data;
     if(offset[7:0]==255 || offset==DIR_BYTES-1)begin page_length<={1'b0,offset[7:0]}+1'b1;state<=DIR_PROGRAM;end
     else begin offset<=offset+1'b1;state<=DIR_FILL;end
    end
    DIR_PROGRAM:io(2,dir_base+{8'd0,page,8'd0},page_length,DIR_WRITE_NEXT);
    DIR_WRITE_NEXT:if(offset==DIR_BYTES-1)begin verify_directory<=1;start_directory_read();end
     else begin page<=page+1'b1;offset<=offset+1'b1;state<=DIR_FILL;end
    DIR_READ:begin
     byte_no<=0;page_length<=DIR_BYTES-{page,8'd0}>=256?9'd256:9'(DIR_BYTES-{page,8'd0});
     io(1,dir_base+{8'd0,page,8'd0},DIR_BYTES-{page,8'd0}>=256?9'd256:9'(DIR_BYTES-{page,8'd0}),DIR_FETCH);
    end
    DIR_FETCH:begin read_index<=byte_no[7:0];state<=DIR_WAIT;end
    DIR_WAIT:state<=DIR_BYTE;
    DIR_BYTE:begin
     if(read_data!=8'hff)bank_nonblank<=1;
     if(!skip_crc)crc<=crc_next;
     if(offset<4)magic<={read_data,magic[31:8]};
     if(offset==4)format<=read_data;if(offset==5)entry_limit<=read_data;
     if(offset>=8 && offset<12)candidate_generation<={read_data,candidate_generation[31:8]};
     if(offset>=12 && offset<16)stored_crc<={read_data,stored_crc[31:8]};
     if(offset>=16 && offset<20)marker<={read_data,marker[31:8]};
     if(offset>=32)begin
      if(offset[4:0]<20)meta_shift<={read_data,meta_shift[159:8]};
      if(offset[4:0]==19)begin
       candidates[(offset-32)>>5]<=parsed_meta;
       if((parsed_meta[7:0]!=0 && parsed_meta[7:0]!=1) ||
        (parsed_meta[7:0]==1 && (parsed_meta[15:8]>32 || parsed_meta[31:16]==0 || parsed_meta[31:16]>MAX_NOTES || parsed_meta[63:32]>3600000)))bad_directory<=1;
       if(parsed_meta[7:0]==1 && parsed_meta[15:8]<=32)begin
        candidate_entries[(offset-32)>>5]<=1;
        if(used_slots[parsed_meta[13:8]])bad_directory<=1;
        used_slots[parsed_meta[13:8]]<=1;
       end
      end
     end
     state<=DIR_NEXT;
    end
    DIR_NEXT:if(offset==DIR_BYTES-1)state<=DIR_CHECK;
     else begin
      offset<=offset+1'b1;
      if(byte_no+1==page_length)begin page<=page+1'b1;state<=DIR_READ;end
      else begin byte_no<=byte_no+1'b1;state<=DIR_FETCH;end
     end
    DIR_CHECK:if(magic!=32'h31435346 || format!=1 || entry_limit!=32 || stored_crc!=(crc^32'hffffffff) || bad_directory ||
       marker!=(verify_directory?32'hffffffff:32'h454e4f44))begin
      if(verify_directory)finish(9);else begin if(bank_nonblank)any_nonblank<=1;state<=BOOT_NEXT;end
     end else if(verify_directory)begin commit_index<=0;state<=MARK_FILL;end
     else if(!have_directory || $signed(candidate_generation-generation)>0)begin meta_index<=0;state<=APPLY;end
     else state<=BOOT_NEXT;
    MARK_FILL:begin
     buffer_write<=1;buffer_index<=commit_index;buffer_wdata<=marker_byte(commit_index[1:0]);
     if(commit_index==3)state<=MARK_PROGRAM;else commit_index<=commit_index+1'b1;
    end
    MARK_PROGRAM:io(2,dir_base+24'd16,4,MARK_READ);
    MARK_READ:begin commit_index<=0;io(1,dir_base+24'd16,4,MARK_FETCH);end
    MARK_FETCH:begin read_index<=commit_index;state<=MARK_WAIT;end
    MARK_WAIT:state<=MARK_CHECK;
    MARK_CHECK:if(read_data!=marker_byte(commit_index[1:0]))finish(9);
     else if(commit_index==3)begin meta_index<=0;state<=APPLY;end
     else begin commit_index<=commit_index+1'b1;state<=MARK_FETCH;end
    APPLY:begin
     catalog[meta_index]<=candidates[meta_index];
     if(meta_index==31)begin
      entries<=candidate_entries;generation<=candidate_generation;active_bank<=dir_base[12];have_directory<=1;
      if(verify_directory)begin
       if(operation==2 && loaded_valid && loaded_index==target)loaded_valid<=0;
       finish(0);
      end else state<=BOOT_NEXT;
     end else meta_index<=meta_index+1'b1;
    end
    BOOT_NEXT:if(!scan_bank)begin scan_bank<=1;dir_base<=24'h001000;start_directory_read();end
     else begin initialized<=1;job_state<=0;error<=(!have_directory && (boot_failed || any_nonblank))?8'h24:8'd0;state<=READY;end
    IO_SEND:if(flash_ready)state<=IO_WAIT;
    IO_WAIT:if(flash_done)begin
     if(flash_error!=0)begin
      if(!initialized)begin boot_failed<=1;state<=BOOT_NEXT;end
      else finish(flash_error);
     end else state<=io_return;
    end
    FINISH:begin done<=1;state<=READY;end
    default:finish(8'h24);
   endcase
  end
 end
 // synthesis translate_off
 initial if(MAX_NOTES<1 || MAX_NOTES>4096)$fatal(1,"invalid library song capacity");
 // synthesis translate_on
endmodule
