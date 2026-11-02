`timescale 1ns/1ps
// Existing10 drum generators/envelopes, with no new ROM or oscillator. Check
// each one-shot stops at its exact documented age even without Note Off.
module tb_percussion_audio;
 reg clk=0,rst=1,ce=0,on=0,restart=0;always #5 clk=~clk;
 reg [4:0] tone=16;wire signed [15:0] sample;wire valid,active;wire [16:0] level;wire [31:0] phase;
 integer checks=0;integer nonzero;
 dds_sine dds(clk,rst,ce,32'd23409859,sample,valid,phase,restart,1'b0,tone);
 instrument_envelope env(.clk(clk),.rst(rst),.sample_ce(ce),.note_on(on),.note_off(1'b0),.restart(restart),.timbre(tone),.level(level),.active(active));
 function automatic integer frames(input integer t);case(t)
  16:frames=12000;17:frames=8640;18:frames=6720;19:frames=3840;20:frames=21600;
  21:frames=16800;22:frames=14400;23:frames=12000;24:frames=72000;default:frames=48000;
 endcase endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s tone=%0d age=%0d",why,tone,env.drum_age);end endtask
 task tick;begin @(negedge clk);ce=1;@(negedge clk);ce=0;end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(integer t=16;t<=25;t++)begin
   tone=5'(t);on=1;restart=1;tick();on=0;restart=0;nonzero=0;
   check(active && level==65536,"new one-shot begins at full envelope");
   for(integer n=0;n<frames(t);n++)begin
    check(active && level>0,"one-shot stays allocated until its defined tail ends");
    tick();check(valid && (^sample!==1'bx),"registered percussion sample always defined");if(sample!=0)nonzero++;
   end
   check(!active && level==0,"one-shot self-releases at exact fixed duration without Off");
   check(nonzero>100,"each retained drum produces a nonzero waveform");
  end
  $display("PASS tb_percussion_audio checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"percussion audio timeout");end
endmodule
