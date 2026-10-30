`timescale 1ns/1ps
// Feed-forward fractional modulated delay, one voice per stereo side. At48kHz
// 20ms centre +/-0.5/1.5/3ms,0.3/0.6/1.2Hz. No feedback/gain boost. RAM is
// never reset; a saturating sample-age check masks history after each reset.
module audio_chorus #(parameter [31:0] PHASE_OFFSET=0)(
 input wire clk,rst,in_valid,input wire signed [15:0] in_sample,
 input wire enabled,input wire [8:0] wet,input wire [1:0] depth,rate,
 output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample);
 reg signed [15:0] memory[0:2047];
 reg [10:0] write_ptr,read_a,read_b;reg [11:0] filled;
 reg signed [15:0] qa,qb,dry,interp;
 reg signed [16:0] difference,blend_difference;
 reg signed [26:0] frac_product,blend_product;
 reg [7:0] fraction;reg [8:0] amount,used_amount;
 reg history_a,history_b;reg [2:0] stage;
 reg [31:0] phase;
 wire [31:0] shifted_phase=phase+PHASE_OFFSET;
 wire [15:0] triangle=shifted_phase[31]?~shifted_phase[30:15]:shifted_phase[30:15];
 wire signed [16:0] bipolar=$signed({1'b0,triangle})-17'sd32768;
 wire [7:0] span=depth==0?8'd24:depth==2?8'd144:8'd72;
 reg [15:0] span_level;
 wire [15:0] span_target={span,8'd0};
 wire signed [33:0] modulation=bipolar*$signed({1'b0,span_level});
 wire signed [25:0] delay_fixed=26'sd245760+(modulation>>>15);
 wire [10:0] delay_integer=delay_fixed[18:8];
 wire [8:0] requested=(enabled===1'b1 && ^wet!==1'bx)?(wet>128?9'd128:wet):9'd0;
 wire accept=in_valid && in_ready;
 assign in_ready=!rst && stage==0;
 // Explicit synchronous no-change ports avoid unsupported READ_BEFORE_WRITE
 // Gowin DPB inference. Writes and reads occupy different clock cycles.
 always @(posedge clk)begin
  if(accept)memory[write_ptr]<=in_sample;
  else qa<=memory[read_a];
 end
 always @(posedge clk)qb<=memory[read_b];
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   write_ptr<=0;read_a<=0;read_b<=0;filled<=0;stage<=0;out_valid<=0;out_sample<=0;
   dry<=0;interp<=0;difference<=0;blend_difference<=0;frac_product<=0;blend_product<=0;
   fraction<=0;amount<=0;used_amount<=0;history_a<=0;history_b<=0;phase<=0;span_level<=18432;
  end else begin
   out_valid<=0;
   if(accept)begin
    dry<=in_sample;used_amount<=amount;
    span_level<=span_level<span_target?(span_target-span_level>16?span_level+16'd16:span_target):
        span_level>span_target?(span_level-span_target>16?span_level-16'd16:span_target):span_level;
    amount<=amount<requested?amount+1'b1:amount>requested?amount-1'b1:amount;
    read_a<=write_ptr-delay_integer;read_b<=write_ptr-delay_integer-11'd1;
    fraction<=delay_fixed[7:0];history_a<=filled>=delay_integer;history_b<=filled>delay_integer;
    write_ptr<=write_ptr+1'b1;if(filled<2048)filled<=filled+1'b1;
    phase<=phase+(rate==0?32'd26844:rate==2?32'd107374:32'd53687);stage<=1;
   end else case(stage)
    1:stage<=2;
    2:begin difference<=$signed(history_b?qb:16'sd0)-$signed(history_a?qa:16'sd0);interp<=history_a?qa:16'sd0;stage<=3;end
    3:begin frac_product<=difference*$signed({1'b0,fraction});stage<=4;end
    4:begin interp<=$signed(interp)+(frac_product>>>8);stage<=5;end
    5:begin blend_difference<=$signed({interp[15],interp})-$signed({dry[15],dry});stage<=6;end
    6:begin blend_product<=blend_difference*$signed({1'b0,used_amount});stage<=7;end
    7:begin out_sample<=$signed(dry)+(blend_product>>>8);out_valid<=1;stage<=0;end
    default:;
   endcase
  end
 end
endmodule
