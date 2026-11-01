`timescale 1ns/1ps
module tb_audio_chorus;
 reg clk=0,rst=1,iv=0,en=0;reg signed [15:0] sample=0;
 reg [8:0] wet=0;reg [1:0] depth=0,rate=0;
 wire rl,rr,vl,vr;wire signed [15:0] l,r;
 integer checks=0,f,code,nn,do_reset,ve,vw,vd,vt,vin,el,er,watch;
 string file_path;
 always #5 clk=~clk;
 audio_chorus left_fx(clk,rst,iv,sample,en,wet,depth,rate,rl,vl,l);
 audio_chorus #(.PHASE_OFFSET(32'h40000000)) right_fx(clk,rst,iv,sample,en,wet,depth,rate,rr,vr,r);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s frame=%0d L=%0d/%0d R=%0d/%0d",why,nn,l,el,r,er);end endtask
 initial begin
  if(!$value$plusargs("VECTORS=%s",file_path))$fatal(1,"vectors missing");f=$fopen(file_path,"r");if(!f)$fatal(1,"open vectors");
  repeat(3)@(negedge clk);rst=0;@(negedge clk);nn=0;
  while(!$feof(f))begin
   code=$fscanf(f,"%d %d %d %d %d %d %d %d\n",do_reset,ve,vw,vd,vt,vin,el,er);
   if(code==8)begin
    if(do_reset)begin rst=1;repeat(2)@(negedge clk);rst=0;@(negedge clk);end
    en=ve;wet=vw;depth=vd;rate=vt;sample=vin;check(rl&&rr,"ready for each frame");iv=1;
    @(negedge clk);iv=0;watch=0;while(!vl&&watch<20)begin @(negedge clk);watch++;end
    check(vl&&vr,"atomic stereo valid");check(l===16'(el)&&r===16'(er),"independent numeric reference");
    @(negedge clk);check(!vl&&!vr,"one output per input");nn++;
   end
  end
  $fclose(f);$display("PASS tb_audio_chorus checks=%0d frames=%0d",checks,nn);$finish;
 end
endmodule
