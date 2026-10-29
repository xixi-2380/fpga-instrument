`timescale 1ns/1ps
// Accelerated component audition. Actual DDS/envelope RTL at 48k sample steps;
// excludes the production mixer, effects, limiter, serializer and board delays.
module tb_midi_audio;
 reg clk=0,rst=1,ce=0,on=0,off=0,restart=0;always #5 clk=~clk;
 reg [4:0] tone=0;reg [31:0] fcw=32'd23409859;wire signed [15:0] sample;wire valid;wire [16:0] level;wire active;
 integer fd,checks=0,energy,pcm;reg [4095:0] outdir,filename;reg signed [34:0] product;
 dds_sine d(.clk(clk),.rst(rst),.sample_ce(ce),.fcw(fcw),.sample(sample),.valid(valid),.restart(restart),.voice_index(1'b0),.timbre(tone));
 instrument_envelope e(.clk(clk),.rst(rst),.sample_ce(ce),.note_on(on),.note_off(off),.restart(restart),.timbre(tone),.level(level),.active(active));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s tone=%0d",why,tone);end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  $sformat(filename,"%0s/audition_pcm.txt",outdir);fd=$fopen(filename,"w");check(fd!=0,"open audition trace");
  for(integer t=0;t<26;t++)begin
   tone=t;rst=1;repeat(4)@(negedge clk);rst=0;energy=0;
   for(integer n=0;n<96000;n++)begin
    @(negedge clk);ce=1;on=n==0;restart=n==0;off=n==24000;
    @(posedge clk);#1;check(valid && (^sample!==1'bx) && (^level!==1'bx),"known registered waveform/envelope");
    product=sample*$signed({1'b0,level});pcm=product>>>16;energy=energy+(pcm<0?-pcm:pcm);$fwrite(fd,"%0d\n",pcm);
    @(negedge clk);ce=0;on=0;off=0;restart=0;repeat(3)@(negedge clk);
   end
   check(energy>1000,"all 26 presets produce audio");check(!active,"released instrument and one-shot drum return idle");
   $display("AUDITION tone=%0d energy=%0d",t,energy);
  end
  $fclose(fd);$display("PASS tb_midi_audio checks=%0d",checks);$finish;
 end
endmodule
