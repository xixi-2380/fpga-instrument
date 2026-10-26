`timescale 1ns/1ps
`include "check.svh"
module tb_audio_spectrum;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 reg signed [15:0] pcm=0;wire [511:0] spectrum;wire ready,update;
 reg [15:0] inputs[0:16383];reg [511:0] old;reg [4095:0] outdir,path;integer checks=0,fd,elapsed;
 audio_spectrum dut(clk,rst,valid,pcm,spectrum,ready,update);
 // Port contract: synchronous reads, and own-port output held on writes.
 // Simultaneous FFT writes must target distinct addresses.
 reg [15:0] before_ar,before_ai,before_br,before_bi;
 reg [10:0] sampled_a,sampled_b;reg wa,wb,check_ports;reg [15:0] sampled_ar,sampled_ai,sampled_br,sampled_bi;
 always @(posedge clk)begin
 before_ar=dut.qa_r;before_ai=dut.qa_i;before_br=dut.qb_r;before_bi=dut.qb_i;
 sampled_a=dut.addr_a;sampled_b=dut.addr_b;wa=dut.write_a;wb=dut.write_fft;
 sampled_ar=dut.data_ar;sampled_ai=dut.data_ai;sampled_br=dut.out_br;sampled_bi=dut.out_bi;
 check_ports=!rst&&(wa||wb);
 #1;
 if(check_ports)begin
 if(wa)begin
 `CHECK(dut.qa_r===before_ar&&dut.qa_i===before_ai,"port A holds read output while writing")
 `CHECK(dut.real_mem[sampled_a]===sampled_ar&&dut.imag_mem[sampled_a]===sampled_ai,"port A store completes")
 end
 if(wb)`CHECK(dut.real_mem[sampled_b]===sampled_br&&dut.imag_mem[sampled_b]===sampled_bi,"port B store completes")
 if(wb)`CHECK(dut.qb_r===before_br&&dut.qb_i===before_bi,"port B holds read output while writing")
 if(wb)`CHECK(sampled_a!=sampled_b,"FFT simultaneous writes target distinct addresses")
 end
 end
 task capture(input integer which);begin
 for(integer n=0;n<2048;n=n+1)begin
 @(negedge clk);pcm=which<0?0:inputs[which*2048+n];valid=1;
 @(negedge clk);valid=0;repeat(2)@(negedge clk);
 end end endtask
 initial begin
 if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
 $sformat(path,"%0s/pcm.hex",outdir);$readmemh(path,inputs);
 $sformat(path,"%0s/fft_actual.txt",outdir);fd=$fopen(path,"w");
 #12 rst=0;repeat(8)@(negedge clk);
 for(integer f=0;f<8;f=f+1)begin
 old=spectrum;capture(f);`CHECK(spectrum==old,"capture never publishes partial FFT")
 elapsed=0;
 while(!update&&elapsed<105000)begin
 @(negedge clk);valid=elapsed==32;pcm=12345;elapsed=elapsed+1;
 `CHECK(update||spectrum==old,"busy samples cannot corrupt published bands")
 end
 valid=0;`CHECK(update&&ready,"bounded complete transform publishes ready")
 if(f==0)`CHECK(spectrum==0,"digital zero spectrum")
 for(integer k=0;k<1024;k=k+1)$fwrite(fd,"%0d %0d %0d %0d\n",f,k,$signed(dut.real_mem[k]),$signed(dut.imag_mem[k]));
 for(integer b=0;b<64;b=b+1)$fwrite(fd,"B %0d %0d %0d\n",f,b,spectrum[b*8+:8]);
 $display("FFT_FRAME %0d analysis_cycles=%0d",f,elapsed);
 repeat(8)@(negedge clk);`CHECK(!update,"one cycle publication")
 end
 $fclose(fd);capture(1);wait(dut.state==6);@(negedge clk);rst=1;#1;
 `CHECK(!ready&&spectrum==0&&!update,"reset interrupts FFT")
 repeat(3)@(negedge clk);rst=0;repeat(8)@(negedge clk);capture(-1);
 elapsed=0;while(!update&&elapsed<105000)begin @(negedge clk);elapsed=elapsed+1;end
 `CHECK(update&&ready&&spectrum==0,"full fresh capture removes stale pre-reset RAM")
 $display("PASS tb_audio_spectrum checks=%0d",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"FFT timeout");end
endmodule
