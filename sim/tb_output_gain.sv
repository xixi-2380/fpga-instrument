`timescale 1ns/1ps
module tb_output_gain;
 reg clk=0,rst=1,nv=0,on=0,flush=0,hard=0;always #8.138020833 clk=~clk;
 reg [6:0] id=60,percent=100;reg [2:0] timbre=0;reg [31:0] fcw=23409859;
 wire nr,ir,bck,ws,din,pa,u,frame_ce,gate;wire [31:0] active,held;wire [16:0] level;
 integer checks=0,frames=0,fd,stage_sample=0,current_code=0,pending_code=0,peak=0,low=0;
 integer word=0,bitn=0,channel=0,pair_code=0;reg synced=0,previous_ws=1;
 reg [4095:0] file;integer last_percent=-1;
 synth_core #(.MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.SUSTAIN(65536),.RELEASE(2)) sound(
 .clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(fcw),.note_timbre(timbre),
 .note_ready(nr),.input_ready(ir),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),.underrun(u),
 .frame_ce(frame_ce),.gate(gate),.voice_active(active),.voice_held(held),.envelope_level(level),
 .effects_enable(1'b0),.effect_mode(2'd0),.effect_cfg_valid(1'b0),.volume_percent(percent),
 .flush(flush),.output_flush(hard),.velocity_valid(1'b0),.note_velocity(7'd127),.note_pitch(id));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task more(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task event_note(input bit yes,input [6:0] ident);begin
  @(negedge clk);nv=1;on=yes;id=ident;wait(nr);@(posedge clk);@(negedge clk);nv=0;
 end endtask
 always @(posedge clk)if(!rst)begin
  check(!u,"production32-voice renderer and limiter meet every frame");
  if(last_percent!=percent)begin $fdisplay(fd,"P %0d",percent);last_percent=percent;end
  if(hard)begin
   stage_sample=0;pending_code=0;
   // Urgent clear drops pending PCM; an already latched I2S word finishes.
   // Do not replace its reference between frame latch and the first MSB.
   if(frame_ce)begin frames++;current_code=0;end
  end
  else begin
   if(frame_ce)begin
    frames++;current_code=pending_code;$fdisplay(fd,"F %0d",stage_sample);stage_sample=0;
   end
   if(sound.effect_valid && !sound.engine_reset)stage_sample=$signed(sound.effect_sample);
   if(sound.limited_valid)$fdisplay(fd,"L %0d %0d",$signed(sound.limited_sample),sound.limiter_gain);
   if(sound.output_valid)begin
    pending_code=$signed(sound.output_sample);$fdisplay(fd,"O %0d",pending_code);
    check(pending_code<=29204 && pending_code>=-29204,"final PCM respects ceiling");
    if(pending_code>peak)peak=pending_code;if(pending_code<low)low=pending_code;
   end
  end
 end
 always @(posedge hard)if(!rst)$fdisplay(fd,"C");
 always @(posedge bck)if(!rst)begin
  if(synced)begin
   if(bitn==0 && channel==0)pair_code=current_code;
   word=((word<<1)|din)&65535;
   if(bitn==15)begin
    check(ws!=previous_ws && ws!=channel,"standard16-bit I2S boundary");
    check(word==(pair_code&65535),"both external I2S channels carry the exact final PCM");
    channel=ws;word=0;bitn=0;
   end else begin check(ws==previous_ws,"sixteen bits per channel");bitn++;end
  end else if(ws!=previous_ws)begin synced=1;channel=ws;word=0;bitn=0;end
  previous_ws=ws;
 end
 initial begin
  if(!$value$plusargs("OUTPUT_TRACE=%s",file))$fatal(1,"Missing trace path");
  fd=$fopen(file,"w");#100 rst=0;wait(ir);more(80);
  for(integer t=0;t<7;t++)begin
   timbre=t;event_note(1,60+t);more(100);peak=0;low=0;more(220);
   check(peak>(t==3 ? 1000 : 14000) && low < -(t==3 ? 1000 : 14000),"native cello retains its slow attack; other timbres reach useful level");
   $display("TIMBRE_LEVEL timbre=%0d positive=%0d negative=%0d",t,peak,low);
   event_note(0,60+t);more(80);
   // Isolate the next preset without spending thousands of frames waiting
   // for its native long release. Envelope timing has its own regression.
   @(negedge clk);flush=1;hard=1;repeat(7)@(negedge clk);flush=0;hard=0;more(70);
  end
  timbre=0;fcw=32'h40000000;
  for(integer v=0;v<32;v++)begin
   @(posedge clk);while(!frame_ce)@(posedge clk);wait(!sound.render_busy);
   event_note(1,32+v);more(3);
  end
  more(180);check(&held,"32-note chord survives output protection");
  percent=50;more(280);check(sound.volume_control.gain==128,"half-volume gain remains exact after limiter");
  percent=0;more(280);check(sound.output_sample==0 && gate,"zero volume preserves voice ownership");
  @(negedge clk);flush=1;hard=1;repeat(7)@(negedge clk);flush=0;hard=0;more(80);
  check(sound.output_sample==0 && sound.volume_control.gain==0,"urgent clear cancels pending PCM while retaining mute");
  percent=100;more(280);check(sound.output_sample==0,"idle stays zero after restoring volume");
  $fclose(fd);$display("PASS tb_output_gain checks=%0d frames=%0d",checks,frames);$finish;
 end
 initial begin #500000000;$fatal(1,"output chain timeout");end
endmodule
