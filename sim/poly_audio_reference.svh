// Override only the DUT hierarchy; the arithmetic/phase reference is unchanged.
`ifndef AUDIO_REF_DUT
`define AUDIO_REF_DUT sound
`define AUDIO_REF_LOCAL_DUT
`endif
// Independent mathematical phase/ROM/fixed-point/serial scoreboard.
integer frames=0,edges=0,bitn=0,ch=0,word=0,nonzero=0,cycles=0,last_frame_cycle=-1;
integer current_code=0,pending_code=0,last_sample=0,romcode;
integer rendered_terms=0,delivered=0,max_delivery_cycle=0,peak_code=0,low_code=0;
reg stalled=0;reg [41:0] stalled_event=0;
reg frame_complete=0;
reg [31:0] ref_phase[0:VOICES-1],phase_for_sample[0:VOICES-1];
reg [11:0] ref_addr[0:VOICES-1];
reg signed [63:0] expected_terms[0:VOICES-1];
reg signed [63:0] reference_term,reference_sum;
real x;
initial for(integer v=0;v<VOICES;v=v+1)ref_phase[v]=0;
always @(posedge rst)begin
 frames=0;edges=0;bitn=0;ch=0;word=0;nonzero=0;current_code=0;pending_code=0;
 last_frame_cycle=-1;frame_complete=0;rendered_terms=0;delivered=0;stalled=0;peak_code=0;low_code=0;
 for(integer v=0;v<VOICES;v=v+1)ref_phase[v]=0;
end
always @(posedge clk)if(!rst)begin
 cycles=cycles+1;
`ifdef TIMBRE_REFERENCE
 if(stalled)begin `CHECK(note_valid && {note_timbre,note_on,note_id,note_fcw}==stalled_event,
  "producer preserves timbre and event until accepted") end
 stalled=note_valid && !note_ready;
 if(stalled)stalled_event={note_timbre,note_on,note_id,note_fcw};
`else
 if(stalled)begin `CHECK(note_valid && {2'b0,note_on,note_id,note_fcw}==stalled_event,
  "producer preserves backpressured event until accepted") end
 stalled=note_valid && !note_ready;
 if(stalled)stalled_event={2'b0,note_on,note_id,note_fcw};
`endif
 `CHECK(!u,"shared output never underruns")
 `CHECK(!`AUDIO_REF_DUT.mix_valid || `AUDIO_REF_DUT.ready,"shared generation meets buffer readiness")
 `CHECK(!`AUDIO_REF_DUT.render_busy || !note_ready,"ownership is frozen throughout render")
 if(`AUDIO_REF_DUT.gain_valid)begin
  `CHECK(`AUDIO_REF_DUT.sample_voice==rendered_terms && rendered_terms<VOICES,"each voice is rendered once in order")
  `CHECK($signed(`AUDIO_REF_DUT.gain_sample)==expected_terms[rendered_terms],"shared voice matches independent exact arithmetic")
  `CHECK(`AUDIO_REF_DUT.phase[rendered_terms*32+:32]==ref_phase[rendered_terms],"shared phase context advances exactly once")
  rendered_terms=rendered_terms+1;
 end
 if(`AUDIO_REF_DUT.mix_valid)begin
  `CHECK(delivered==0 && rendered_terms==VOICES,"one complete mixed result per frame")
  `CHECK($signed(`AUDIO_REF_DUT.mix_sample)==pending_code,"full mix matches independent mathematical sum")
  `CHECK(cycles-last_frame_cycle<=32+16*VOICES,"render meets fixed frame budget")
  if(cycles-last_frame_cycle>max_delivery_cycle)max_delivery_cycle=cycles-last_frame_cycle;
  delivered=delivered+1;
 end
 if(frame_ce)begin
  if(last_frame_cycle>=0)begin
   `CHECK(cycles-last_frame_cycle==1280,"audio never stalls the 1280-cycle frame")
   `CHECK(delivered==1,"previous frame had exactly one buffer delivery")
  end
  last_frame_cycle=cycles;current_code=pending_code;rendered_terms=0;delivered=0;
  for(integer v=0;v<VOICES;v=v+1)begin
   phase_for_sample[v]=`AUDIO_REF_DUT.voice_restart[v]?0:ref_phase[v];
   ref_addr[v]=phase_for_sample[v][31:20];
   ref_phase[v]=phase_for_sample[v]+`AUDIO_REF_DUT.voice_fcw[v*32+:32];
  end
  #0.001;reference_sum=0;
  for(integer v=0;v<VOICES;v=v+1)begin
   x=$sin(6.283185307179586*ref_addr[v]/4096.0)*32767.0;
`ifdef TIMBRE_REFERENCE
   x=waveform(`AUDIO_REF_DUT.frame_timbres[v*2+:2],6.283185307179586*ref_addr[v]/4096.0)
      /peaks[`AUDIO_REF_DUT.frame_timbres[v*2+:2]]*32767.0;
`endif
   romcode=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);
   reference_term=`AUDIO_REF_DUT.voice_level[v];
   reference_term=reference_term*`AUDIO_REF_DUT.startup_level;reference_term=reference_term>>>16;
   reference_term=reference_term*romcode;reference_term=reference_term>>>13;
   expected_terms[v]=reference_term;reference_sum=reference_sum+reference_term;
  end
  reference_sum=reference_sum>>>8;
  if(reference_sum>32767)pending_code=32767;
  else if(reference_sum < -32768)pending_code=-32768;
  else pending_code=reference_sum;
 end
end
always @(posedge bck)if(!rst)begin
 frame_complete=0;edges=edges+1;
 `CHECK(ws==(ch==1),"PT8211 stereo framing")
 word=((word<<1)|din)&65535;
 if(bitn==15)begin
  `CHECK(word==(current_code&65535),"shared output matches exact per-frame reference")
  `CHECK($signed(word[15:0])>=-VOICES*1024 && $signed(word[15:0])<=VOICES*1024-1,"configured voice gain headroom")
  if($signed(word[15:0])>peak_code)peak_code=$signed(word[15:0]);
  if($signed(word[15:0])<low_code)low_code=$signed(word[15:0]);
  if(word!=0)nonzero=nonzero+1;
  if(ch==1)begin frames=frames+1;last_sample=$signed(word[15:0]);frame_complete=1;end
  ch=1-ch;word=0;bitn=0;
 end else bitn=bitn+1;
end
task more_frames(input integer n);integer target;begin
 target=frames+n;wait(frames>=target);#2;
end endtask


`ifdef AUDIO_REF_LOCAL_DUT
`undef AUDIO_REF_DUT
`undef AUDIO_REF_LOCAL_DUT
`endif
