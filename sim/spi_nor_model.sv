`timescale 1ns/1ps
// Independent wire-level mode-0 NOR model; not part of the Gowin project.
// Memory survives FPGA reset. Programs permit only 1->0, erase is 4KiB.
module spi_nor_model #(parameter integer BYTES=2228224,PROGRAM_BUSY_CYCLES=100,ERASE_BUSY_CYCLES=200)(
 input wire clk,cs_n,sck,mosi,output reg miso=1,
 input wire [23:0] device_id,input wire protected_mode,stuck_busy,
 output integer programs=0,erases=0);
 reg [7:0] memory[0:BYTES-1];reg [7:0] input_byte=0,command=0,output_byte=8'hff;
 // Status-register locks/geometry are distinct from array protection.
 reg [7:0] sr1_flags=0,sr2_flags=0,sr3_flags=0;
 integer forbidden_writes=0;
 // Fixtures may specify the protected address interval independently from
 // register flags, or actual per-sector locks. This does not duplicate the
 // driver's permission predicate and can expose an over-broad software gate.
 reg range_lock_enabled=0;reg [23:0] protected_first=0,protected_last=0;
 reg [(BYTES+4095)/4096-1:0] sector_locked='1;
 function automatic array_writable(input [23:0] a);
 begin
  if(protected_mode || sr2_flags[7])array_writable=0;
  else if(sr3_flags[2])array_writable=a<BYTES && !sector_locked[a>>12];
  else if(range_lock_enabled)array_writable=a<protected_first || a>protected_last;
  else array_writable=sr1_flags[4:2]==0 && !sr2_flags[6];
 end endfunction
 reg [23:0] address=0;integer bits=0,byte_index=0,busy_cycles=0;reg wel=0;
 initial for(integer i=0;i<BYTES;i++)memory[i]=8'hff;
 always @(posedge clk)if(busy_cycles>0)busy_cycles<=busy_cycles-1;
 always @(negedge cs_n)begin bits=0;byte_index=0;input_byte=0;command=0;address=0;end
 always @(posedge sck)if(!cs_n)begin
  input_byte={input_byte[6:0],mosi};
  if(bits==7)begin
   bits=0;
   if(byte_index==0)command=input_byte;
   else if((command==8'h03 || command==8'h02 || command==8'h20) && byte_index<=3)address={address[15:0],input_byte};
   else if(command==8'h02 && byte_index>=4)begin
    if(wel && array_writable(address) && !stuck_busy && busy_cycles==0 && address<BYTES)memory[address]=memory[address]&input_byte;
    address={address[23:8],address[7:0]+8'd1};
   end else if(command==8'h03 && byte_index>=4)address=address+1'b1;
   byte_index=byte_index+1;
  end else bits=bits+1;
 end
 always @(negedge sck)if(!cs_n)begin
  if(bits==0)begin
   output_byte=8'hff;
   case(command)
    8'h9f:case(byte_index)1:output_byte=device_id[23:16];2:output_byte=device_id[15:8];3:output_byte=device_id[7:0];default:output_byte=8'hff;endcase
    8'h05:output_byte=(sr1_flags & 8'hfc) | (protected_mode?8'h04:8'h00) | {6'd0,wel,(busy_cycles!=0 || stuck_busy)};
    8'h35:output_byte=sr2_flags;8'h15:output_byte=sr3_flags;
    8'h03:if(byte_index>=4 && address<BYTES)output_byte=memory[address];
    default:;
   endcase
  end
  miso=output_byte[7-bits];
 end
 always @(posedge cs_n)begin
  if(command==8'h01 || command==8'h31 || command==8'h11 || command==8'h50 || command==8'h98 || command==8'hc7 || command==8'h60)forbidden_writes=forbidden_writes+1;
  if(command==8'h06 && !protected_mode && !stuck_busy && busy_cycles==0)wel=1;
  if(command==8'h02 && byte_index>4 && wel && array_writable(address) && !stuck_busy && busy_cycles==0)begin programs=programs+1;wel=0;busy_cycles=PROGRAM_BUSY_CYCLES;end
  if(command==8'h20 && byte_index==4 && wel && array_writable(address) && !stuck_busy && busy_cycles==0)begin
   for(integer i=0;i<4096;i++)if({address[23:12],12'd0}+i<BYTES)memory[{address[23:12],12'd0}+i]=8'hff;
   erases=erases+1;wel=0;busy_cycles=ERASE_BUSY_CYCLES;
  end
  miso=1;
 end
endmodule
