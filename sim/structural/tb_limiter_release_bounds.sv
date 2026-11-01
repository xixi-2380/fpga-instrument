`timescale 1ns/1ps
module tb_limiter_release_bounds;
 reg [16:0] value=0,target=0;reg [14:0] error_value=0;
 wire [28:0] current_total[1:15],reference_total[1:15];
 wire [16:0] current_next[1:15],reference_next[1:15];
 integer checks=0,seed=32'h239015ab;
 for(genvar shift=1;shift<=15;shift++)begin:lanes
  audio_limiter #(.RELEASE_SHIFT(shift)) dut(.clk(1'b0),.rst(1'b0),.in_valid(1'b0),.in_sample(16'sd0),.in_tag(17'd0));
  reference_audio_limiter_c6352fa #(.RELEASE_SHIFT(shift)) ref_dut(.clk(1'b0),.rst(1'b0),.in_valid(1'b0),.in_sample(16'sd0),.in_tag(17'd0));
  initial begin
   force dut.released=value;force ref_dut.released=value;
   force dut.release_error=error_value[shift-1:0];force ref_dut.release_error=error_value[shift-1:0];
   force dut.target=target;force ref_dut.target=target;
  end
  assign current_total[shift]=dut.recovery_total;
  assign reference_total[shift]=ref_dut.recovery_total;
  assign current_next[shift]=dut.next_release;
  assign reference_next[shift]=ref_dut.next_release;
 end
 initial begin
  for(integer r=0;r<=65536;r++)begin
   value=r;
   for(integer e=0;e<5;e++)begin
    case(e)0:error_value=0;1:error_value=1;2:error_value=16384;3:error_value=32766;4:error_value=32767;endcase
    target=17'($unsigned($random(seed))%65537);#1;
    for(integer s=1;s<=15;s++)begin
     checks++;
     if(current_total[s]!==reference_total[s] || current_next[s]!==reference_next[s])
      $fatal(1,"release mismatch value=%0d error=%0d shift=%0d",value,error_value,s);
     if(current_total[s]>98303 || current_next[s]>65536)$fatal(1,"bounded release invariant violated");
    end
   end
  end
  $display("PASS tb_limiter_release_bounds checks=%0d",checks);$finish;
 end
endmodule
