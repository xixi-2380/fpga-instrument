// Independent sine/rounding/40-bit mix and PT8211 serial scoreboard.
// Allocation and ADSR timing have separate unit references; only their public
// slot commands/levels are observed here to check the entire sample pipeline.
integer frames=0,edges=0,bitn=0,ch=0,word=0,nonzero=0,cycles=0,last_frame_cycle=-1;
integer current_code=0,pending_code=0,last_sample=0,romcode;
reg frame_complete=0;
reg [31:0] ref_phase[0:3],phase_for_sample[0:3];
reg [11:0] ref_addr[0:3];
reg signed [63:0] reference_term,reference_sum;
real x;
initial for(integer v=0;v<4;v=v+1)ref_phase[v]=0;
always @(posedge rst)begin
 frames=0;edges=0;bitn=0;ch=0;word=0;nonzero=0;current_code=0;pending_code=0;
 last_frame_cycle=-1;frame_complete=0;
 for(integer v=0;v<4;v=v+1)ref_phase[v]=0;
end
always @(posedge clk)if(!rst)begin
 cycles=cycles+1;
 `CHECK(!u,"four-voice output never underruns")
 `CHECK(!sound.mix_valid || sound.ready,"four-voice generation meets next-frame buffer deadline")
 `CHECK(sound.gain_valid==4'b0000 || sound.gain_valid==4'b1111,"voice pipelines remain aligned")
 if(frame_ce)begin
  if(last_frame_cycle>=0)begin `CHECK(cycles-last_frame_cycle==1280,"polyphony never stalls the 1280-cycle frame") end
  last_frame_cycle=cycles;current_code=pending_code;
  for(integer v=0;v<4;v=v+1)begin
   phase_for_sample[v]=sound.voice_restart[v]?0:ref_phase[v];
   ref_addr[v]=phase_for_sample[v][31:20];
   ref_phase[v]=phase_for_sample[v]+sound.voice_fcw[v*32+:32];
  end
  #0.001;reference_sum=0;
  for(integer v=0;v<4;v=v+1)begin
   x=$sin(6.283185307179586*ref_addr[v]/4096.0)*32767.0;
   romcode=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);
   reference_term=sound.voice_level[v];
   reference_term=reference_term*sound.startup_level;reference_term=reference_term>>>16;
   reference_term=reference_term*romcode;reference_term=reference_term>>>13;
   reference_sum=reference_sum+reference_term;
  end
  reference_sum=reference_sum>>>8;
  if(reference_sum>32767)pending_code=32767;
  else if(reference_sum < -32768)pending_code=-32768;
  else pending_code=reference_sum;
 end
end
always @(posedge bck)if(!rst)begin
 frame_complete=0;edges=edges+1;
 `CHECK(ws==(ch==1),"polyphonic PT8211 stereo framing")
 word=((word<<1)|din)&65535;
 if(bitn==15)begin
  `CHECK(word==(current_code&65535),"four sine voices reach serial output with exact fixed-point mix")
  `CHECK($signed(word[15:0])>=-4096 && $signed(word[15:0])<=4095,"four voices preserve configured gain headroom")
  if(word!=0)nonzero=nonzero+1;
  if(ch==1)begin frames=frames+1;last_sample=$signed(word[15:0]);frame_complete=1;end
  ch=1-ch;word=0;bitn=0;
 end else bitn=bitn+1;
end
task more_frames(input integer n);integer target;begin
 target=frames+n;wait(frames>=target);#2;
end endtask
