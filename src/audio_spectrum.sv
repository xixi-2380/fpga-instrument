`timescale 1ns/1ps
// Passive48kHz tap:2048-point Hann-windowed scaled radix-2 DIT FFT.
// Analysis skips busy samples; audio is never stalled. One window multiplier
// and one time-shared complex rotation multiplier, synchronous dual-port RAM.
module audio_spectrum(input wire clk,rst,sample_valid,input wire signed [15:0] sample,
 output reg [511:0] spectrum,output reg ready,output reg update_valid);
 localparam [4:0] CAP=0,FLUSH=1,RD=2,M0=3,M1=4,M2=5,M3=6,ROT=7,SUM=8,WR=9,
 BRD=10,BMAG=11,BACC=12,LOG0=13,LOG1=14,LOG2=15,PUBLISH=16;
 reg [4:0] state;
 reg signed [15:0] real_mem[0:2047],imag_mem[0:2047];
 reg [15:0] window_rom[0:2047];reg [31:0] twiddle_rom[0:1023];reg [10:0] bands[0:64];
 initial begin
 $readmemh("src/rom/fft_window.hex",window_rom);
 $readmemh("src/rom/fft_twiddle.hex",twiddle_rom);
 $readmemh("src/rom/fft_bands.hex",bands);
 end
 function automatic [10:0] reverse_bits(input [10:0] v);
 for(integer k=0;k<11;k=k+1)reverse_bits[k]=v[10-k];endfunction
 function automatic [15:0] abs16(input signed [15:0] v);
 abs16=v[15] ? (~v+16'd1) : v;endfunction
 function automatic signed [15:0] saturate(input signed [18:0] v);
 if(v>32767)saturate=16'sh7fff;else if(v< -32768)saturate=16'sh8000;else saturate=v[15:0];endfunction
 function automatic [4:0] leading_bit(input [16:0] m);
 reg [3:0] nibble;reg [4:0] offset;
 begin
 if(m[16])begin nibble=1;offset=16;end
 else if(|m[15:12])begin nibble=m[15:12];offset=12;end
 else if(|m[11:8])begin nibble=m[11:8];offset=8;end
 else if(|m[7:4])begin nibble=m[7:4];offset=4;end
 else begin nibble=m[3:0];offset=0;end
 leading_bit=offset+(nibble[3]?5'd3:nibble[2]?5'd2:nibble[1]?5'd1:5'd0);
 end endfunction
 reg [16:0] format_magnitude;
 reg [4:0] format_exponent;reg [19:0] format_shifted;reg [7:0] format_level;
 wire [7:0] log_peak=format_magnitude==0?0:format_level>127?127:format_level;
 reg [10:0] captured,pending_addr,base,half,j,tw_step,bin_index;
 reg [9:0] tw_index;reg [5:0] band_index;reg pending;
 reg signed [31:0] window_product,product;reg [15:0] window_q;reg [31:0] twiddle_q;
 wire signed [15:0] wr=$signed(twiddle_q[31:16]),wi=$signed(twiddle_q[15:0]);
 reg signed [15:0] qa_r,qa_i,qb_r,qb_i,a_r,a_i,out_ar,out_ai,out_br,out_bi;
 reg signed [32:0] accum,rotated_real;reg signed [17:0] t_r,t_i;
 wire signed [15:0] mul_a=(state==M1||state==M3)?qb_i:qb_r;
 wire signed [15:0] mul_b=(state==M1||state==M2)?wi:wr;
 wire signed [18:0] a_ext_r={{3{a_r[15]}},a_r},a_ext_i={{3{a_i[15]}},a_i};
 wire signed [18:0] t_ext_r={t_r[17],t_r},t_ext_i={t_i[17],t_i};
 wire [11:0] next_base={1'b0,base}+({1'b0,half}<<1);
 wire [10:0] fft_a=base+j,fft_b=base+j+half;
 wire analyzing=state==BRD||state==BMAG||state==BACC;
 wire [10:0] addr_a=pending?pending_addr:analyzing?bin_index:fft_a;
 wire [10:0] addr_b=fft_b;wire write_fft=state==WR;
 // Explicit normal/no-change dual-port RAM: hold each read register on
 // writes to its own port. Unconditional reads here infer read-before-write
 // (DPB WRITE_MODE=2'b10), rejected by this device with PA2122.
 // The FSM reads in RD/BRD after WR; write-cycle outputs are never consumed.
 // No array/read-register reset; a full capture overwrites RAM before use.
 wire write_a=pending||write_fft;
 wire signed [15:0] data_ar=pending?(window_product>>>15):out_ar;
 wire signed [15:0] data_ai=pending?16'sd0:out_ai;
 always @(posedge clk)begin
 window_q<=window_rom[captured];twiddle_q<=twiddle_rom[tw_index];
 end
 // One synchronous process per physical RAM port, conventional inference.
 always @(posedge clk)begin
 if(write_a)real_mem[addr_a]<=data_ar;
 else qa_r<=real_mem[addr_a];
 end
 always @(posedge clk)begin
 if(write_fft)real_mem[addr_b]<=out_br;
 else qb_r<=real_mem[addr_b];
 end
 always @(posedge clk)begin
 if(write_a)imag_mem[addr_a]<=data_ai;
 else qa_i<=imag_mem[addr_a];
 end
 always @(posedge clk)begin
 if(write_fft)imag_mem[addr_b]<=out_bi;
 else qb_i<=imag_mem[addr_b];
 end
 reg [511:0] working;reg [16:0] magnitude,band_peak;
 wire [16:0] final_peak=magnitude>band_peak?magnitude:band_peak;
 wire last_bin=bin_index==bands[{1'b0,band_index}+7'd1]-11'd1;
 for(genvar b=0;b<64;b=b+1)begin:bar_words
 always @(posedge clk or posedge rst)
 if(rst)working[b*8+:8]<=0;
 else if(state==PUBLISH&&band_index==b)working[b*8+:8]<=log_peak;
 end
 always @(posedge clk or posedge rst)begin
 if(rst)begin
 state<=CAP;captured<=0;pending<=0;pending_addr<=0;window_product<=0;
 base<=0;half<=1;j<=0;tw_step<=1024;tw_index<=0;bin_index<=0;band_index<=0;
 product<=0;accum<=0;rotated_real<=0;t_r<=0;t_i<=0;a_r<=0;a_i<=0;
 out_ar<=0;out_ai<=0;out_br<=0;out_bi<=0;magnitude<=0;band_peak<=0;
 spectrum<=0;ready<=0;update_valid<=0;format_magnitude<=0;format_exponent<=0;format_shifted<=0;format_level<=0;
 end else begin
 update_valid<=0;pending<=0;
 if(state>=M0&&state<=M3)product<=mul_a*mul_b;
 case(state)
 CAP:if(sample_valid)begin
 window_product<=sample*$signed({1'b0,window_q});pending_addr<=reverse_bits(captured);pending<=1;
 if(captured==2047)begin captured<=0;state<=FLUSH;end else captured<=captured+1'b1;
 end
 FLUSH:begin base<=0;half<=1;j<=0;tw_step<=1024;tw_index<=0;state<=RD;end
 RD:state<=M0;
 M0:begin a_r<=qa_r;a_i<=qa_i;state<=M1;end
 M1:begin accum<={product[31],product};state<=M2;end
 M2:begin rotated_real<=accum-$signed(product);state<=M3;end
 M3:begin accum<={product[31],product};state<=ROT;end
 ROT:begin t_r<=rotated_real>>>14;t_i<=(accum+$signed(product))>>>14;state<=SUM;end
 SUM:begin
 out_ar<=saturate((a_ext_r+t_ext_r)>>>1);out_ai<=saturate((a_ext_i+t_ext_i)>>>1);
 out_br<=saturate((a_ext_r-t_ext_r)>>>1);out_bi<=saturate((a_ext_i-t_ext_i)>>>1);state<=WR;
 end
 WR:begin
 if(j==half-1)begin
 j<=0;tw_index<=0;
 if(next_base==2048)begin
 base<=0;
 if(half==1024)begin bin_index<=0;band_index<=0;band_peak<=0;state<=BRD;end
 else begin half<=half<<1;tw_step<=tw_step>>1;state<=RD;end
 end else begin base<=next_base[10:0];state<=RD;end
 end else begin j<=j+1'b1;tw_index<=tw_index+tw_step;state<=RD;end
 end
 BRD:state<=BMAG;
 BMAG:begin magnitude<={1'b0,abs16(qa_r)}+{1'b0,abs16(qa_i)};state<=BACC;end
 BACC:begin
 if(last_bin)begin band_peak<=0;format_magnitude<=final_peak;state<=LOG0;end
 else begin band_peak<=final_peak;bin_index<=bin_index+1'b1;state<=BRD;end
 end
 // Registered exponent, normalization, packing: no long combinational chain.
 LOG0:begin format_exponent<=leading_bit(format_magnitude);state<=LOG1;end
 LOG1:begin format_shifted<={format_magnitude,3'b000}>>format_exponent;state<=LOG2;end
 LOG2:begin format_level<={format_exponent,3'b000}+{5'd0,format_shifted[2:0]};state<=PUBLISH;end
 PUBLISH:begin
 if(band_index==63)begin spectrum<={log_peak,working[503:0]};ready<=1;update_valid<=1;state<=CAP;end
 else begin band_index<=band_index+1'b1;bin_index<=bin_index+1'b1;state<=BRD;end
 end
 default:state<=CAP;
 endcase
 end
 end
endmodule
