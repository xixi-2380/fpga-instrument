`timescale 1ns/1ps
// End-to-end manual-key/arbiter/allocator/envelope release checks.
module tb_release_drain;
 parameter integer VOICES=4;
 localparam integer FRAME=128;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg admission=1,blocked=0,snapshot=1;
 reg [35:0] piano=0;reg [2:0] online=7;
 reg [4:0] timbre=0;reg sustain=1;
 reg [7:0] phase=0;reg engine_admit=1;
 always @(posedge clk)if(rst)phase<=0;else phase<=phase==FRAME-1?0:phase+1'b1;
 wire ce=!rst && phase==0;
 wire allocate_enable=engine_admit && phase>=8 && phase<112;
 wire [35:0] keys;wire key_valid,key_on,key_ready;
 wire [6:0] key_id;wire [31:0] key_fcw;wire [4:0] key_timbre;wire [5:0] last_key;
 wire [VOICES-1:0] held,active,start,stop,restart;
 wire [VOICES*32-1:0] fcw;wire [VOICES*7-1:0] ids,pitches;wire [VOICES*5-1:0] timbres;wire [VOICES*9-1:0] gains;
 wire ready,valid,on,expressive;wire [6:0] id,pitch,velocity;wire [31:0] frequency;wire [4:0] tone;
 reg b_valid=0,b_on=0;wire b_ready;
 wire [16:0] levels[0:VOICES-1];
 touch_keyboard_router #(.AUX_ENABLE(0)) router(
  .clk(clk),.rst(rst),.blocked(blocked),.menu_mode(blocked),.more_mode(1'b0),.ultrasonic_page(1'b0),
  .snapshot_valid(snapshot),.piano(piano),.aux(12'd0),.online(online),.note_keys(keys));
 key_note_events #(.KEYS(36)) events(
  .clk(clk),.rst(rst),.enabled(admission),.keys(keys),.note_ready(key_ready),
  .note_valid(key_valid),.note_on(key_on),.note_id(key_id),.note_fcw(key_fcw),
  .last_key(last_key),.selected_timbre(timbre),.note_timbre(key_timbre));
 manual_event_arbiter arbiter(
  .clk(clk),.rst(rst),.a_valid(key_valid),.a_on(key_on),.b_valid(b_valid),.b_on(b_on),
  .a_id(key_id),.b_id(7'd96),.a_fcw(key_fcw),.b_fcw(32'h0258bf26),.a_timbre(key_timbre),.b_timbre(5'd5),
  .b_pitch(7'd69),.b_velocity(7'd100),.ready(ready),.a_ready(key_ready),.b_ready(b_ready),
  .valid(valid),.on(on),.id(id),.pitch(pitch),.velocity(velocity),.fcw(frequency),.timbre(tone),.expressive(expressive));
 voice_allocator #(.VOICES(VOICES),.AUTOMATIC_IDS(16),.PRESERVE_MANUAL_TAILS(1)) allocator(
  .clk(clk),.rst(rst),.enabled(allocate_enable),.frame_ce(ce),.note_valid(valid),.note_on(on),
  .note_id(id),.note_fcw(frequency),.voice_active(active),.note_ready(ready),
  .voice_start(start),.voice_stop(stop),.voice_restart(restart),.voice_held(held),
  .voice_fcw(fcw),.voice_ids(ids),.note_timbre(tone),.voice_timbres(timbres),
  .note_independent(expressive),.note_gain(9'd256),.note_pitch(pitch),.voice_gains(gains),.voice_pitches(pitches));
 for(genvar v=0;v<VOICES;v++)begin: voices
  wire [16:0] native_level;wire native_active;
  instrument_envelope #(.ATTACK(3),.DECAY(5),.RELEASE(7)) native_envelope(
   .clk(clk),.rst(rst),.sample_ce(ce),.note_on(start[v]),.note_off(stop[v]),.restart(restart[v]),
   .timbre(timbres[v*5+:5]),.level(native_level),.active(native_active));
  sustain_envelope #(.PRECALC(1)) tail(
   .clk(clk),.rst(rst),.sample_ce(ce),.note_on(start[v]),.note_off(stop[v]),.enabled(sustain),
   .base_level(native_level),.base_active(native_active),.duration(17'd257),
   .phase_step(17'd65280),.phase_remainder(17'd256),.strength(9'd64),
   .level(levels[v]),.active(active[v]));
 end
 integer checks=0,accepted_on=0,accepted_off=0,seed=32'h2380f11e;
 reg stalled=0;reg [45:0] previous;
 always @(posedge clk)begin
  if(rst)stalled<=0;
  else begin
   checks++;
   if(stalled && (!valid || {on,id,frequency,tone,expressive}!==previous))
    $fatal(1,"Manual event changed while allocator was searching");
   stalled<=valid && !ready;
   previous<={on,id,frequency,tone,expressive};
   if(valid && ready)begin
    if(on)accepted_on++;else accepted_off++;
   end
  end
 end
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task frames(input integer n);begin clocks(n*FRAME);end endtask
 task require_silent(input integer n,input [511:0] label);
 begin
  frames(n+270);
  if(held!==0 || key_valid!==0 || events.reported_keys!==0 || active!==0)
   $fatal(1,"%0s held=%h active=%h reported=%h valid=%b",label,held,active,events.reported_keys,key_valid);
  for(integer v=0;v<VOICES;v++)if(levels[v]!==0)$fatal(1,"Nonzero envelope after release");
  checks++;
 end endtask
 task pluck(input bit n);integer timeout;begin
  b_on=n;b_valid=1;timeout=0;
  while(!b_ready)begin clocks(1);timeout++;if(timeout>1000)$fatal(1,"Arbiter B starved");end
  @(posedge clk);@(negedge clk);b_valid=0;
 end endtask
 initial begin
  clocks(3);rst=0;clocks(8);
  // Known reproduction: an admitted note remains owned when admission is
  // disabled before physical release. The old adapter suppresses its Off.
  piano=1;frames(20);
  if(held==0 || events.reported_keys!=1)$fatal(1,"Setup note was not admitted");
  admission=0;piano=0;
  require_silent(30,"release stranded while admission disabled");
  // New starts are blocked, but pending release delivery remains live.
  piano=2;frames(10);
  if(held!=0 || key_valid)$fatal(1,"Disabled admission accepted a new press");
  piano=0;clocks(8);admission=1;
  // A legitimate long hold must not be hidden by a watchdog time limit.
  sustain=0;timbre=0;piano=4;frames(100);
  if(held==0 || active==0)$fatal(1,"Legitimate long hold was cut off");
  blocked=1;require_silent(30,"menu release did not drain");
  blocked=0;frames(10);if(held!=0)$fatal(1,"Menu exit retriggered a held key");
  piano=0;clocks(8);piano=4;frames(20);
  online=6;require_silent(30,"disconnect release did not drain");
  online=7;frames(10);if(held!=0)$fatal(1,"Reconnect retriggered a held key");
  piano=0;clocks(8);piano=4;frames(20);snapshot=0;
  require_silent(30,"invalid snapshot release did not drain");
  snapshot=1;frames(10);if(held!=0)$fatal(1,"Snapshot recovery retriggered held key");
  piano=0;clocks(8);sustain=1;
  // Rapid arbitrary snapshots with engine backpressure and all36 physical
  // keys exercise stealing/retrigger tails. The final all-up must converge.
  for(integer n=0;n<1500;n++)begin
   piano[$unsigned($random(seed))%36]=~piano[$unsigned($random(seed))%36];
   if(n%17==0)timbre=5'($unsigned($random(seed))%16);
   if(n%43==0)engine_admit=0;
   if(n%43==9)engine_admit=1;
   clocks(11+n%7);
  end
  piano=0;admission=0;engine_admit=1;
  require_silent(100,"randomized final release did not drain");
  // Physical and touch source payloads share allocator backpressure.
  admission=1;pluck(1);piano=36'hfffffffff;frames(60);pluck(0);
  piano=0;admission=0;require_silent(100,"touch/physical chord did not drain");
  // Reset during a backpressured press cannot leave an old owner behind.
  admission=1;engine_admit=0;piano=1;clocks(20);rst=1;piano=0;b_valid=0;
  clocks(3);rst=0;engine_admit=1;
  require_silent(30,"reset left phantom ownership");
  if(accepted_on<10 || accepted_off<10)$fatal(1,"Insufficient stress coverage");
  $display("PASS tb_release_drain voices=%0d checks=%0d ons=%0d offs=%0d",VOICES,checks,accepted_on,accepted_off);$finish;
 end
 initial begin #20000000;$fatal(1,"Release drain timeout");end
endmodule
