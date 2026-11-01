`timescale 1ns/1ps
module tb_audio_output_filter;
 reg clk=0,rst=1,in_valid=0,silence=0;always #5 clk=~clk;
 reg signed [15:0] in_sample=0;reg [16:0] in_tag=0;
 wire out_valid;wire signed [15:0] out_sample;wire [16:0] out_tag;
 audio_output_filter dut(.clk(clk),.rst(rst),.in_valid(in_valid),.in_sample(in_sample),.in_tag(in_tag),.silence(silence),.out_valid(out_valid),.out_sample(out_sample),.out_tag(out_tag));
 reg [69:0] vectors[0:1200000];reg [8191:0] path;
 integer count=0,checks=0,outputs=0,descriptor,read_status;reg [69:0] vector;
 initial begin
  if(!$value$plusargs("VECTORS=%s",path))$fatal(1,"Missing vectors");
  descriptor=$fopen(path,"r");if(!descriptor)$fatal(1,"Cannot open vectors");
  read_status=$fscanf(descriptor,"%h",vector);$fclose(descriptor);
  if(read_status!=1)$fatal(1,"Cannot read vector count");count=vector;
  if(count<1 || count>1200000)$fatal(1,"Invalid vector count");
  $readmemh(path,vectors,0,count);
  for(integer n=1;n<=count;n++)begin
   @(negedge clk);vector=vectors[n];
   rst=vector[69];in_valid=vector[68];silence=vector[67];in_sample=vector[66:51];in_tag=vector[50:34];
   @(posedge clk);#0.001;checks++;
   if(out_valid!==vector[33])$fatal(1,"Valid mismatch n=%0d expected=%0d got=%0d",n,vector[33],out_valid);
   if(vector[33])begin
    outputs++;
    if({out_sample,out_tag}!==vector[32:0])$fatal(1,"PCM/tag mismatch n=%0d got=%0d/%0d expected=%0d/%0d",n,out_sample,out_tag,$signed(vector[32:17]),vector[16:0]);
   end
   if(rst && {out_valid,out_sample,out_tag}!==34'd0)$fatal(1,"Reset did not clear output");
  end
  $display("PASS tb_audio_output_filter checks=%0d outputs=%0d",checks,outputs);$finish;
 end
endmodule
