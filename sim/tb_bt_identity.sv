`timescale 1ns/1ps
// MIDI onset groups -> actual upload/core/player -> CDC -> top mux -> allocator.
// Includes unison notes: pitch is deliberately NOT used as ownership identity.
module tb_bt_identity;
 parameter integer TIMBRE=0;
 reg clk=0,rst=1,rv=0;reg [7:0] rb=0;
 always #10 clk=~clk;
 keyboard_top #(.LCD_ENABLE(1),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),
 .MUTE(1),.FADE(1),.ATTACK(2),.DECAY(2),.SUSTAIN(65536),.RELEASE(2)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.keypad_int_n(3'b111),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),.flash_miso(1'b1));
 reg [63:0] records[0:28];reg signed [15:0] wave[0:4095];
 reg [7:0] payload[0:255],response[0:31];reg [31:0] crc32;
 reg [15:0] logical_held=0;reg [6:0] pitches[0:15],velocities[0:15];
 reg [31:0] phase[0:31];reg signed [63:0] expected[0:31],term,total;
 reg [8:0] physical_gain[0:31];reg [6:0] physical_pitch[0:31];
 integer checks=0,ons=0,offs=0,replies=0,rxn=0,goal=0,terms=0,peak=0;
 reg [31:0] phase_now;reg signed [15:0] expected_mix;
 string directory,notes_file;
 function automatic [15:0] crc16(input [15:0] c,input [7:0] b);reg [15:0] x;
 begin x=c^{b,8'b0};for(integer k=0;k<8;k++)x=(x<<1)^(x[15]?16'h1021:0);crc16=x;end endfunction
 function automatic [31:0] crc_byte(input [31:0] c,input [7:0] b);reg [31:0] x;
 begin x=c^b;for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);crc_byte=x;end endfunction
 function automatic [31:0] frequency(input [6:0] p);
 case(p)48:frequency=11704930;52:frequency=14747287;55:frequency=17537579;
 60:frequency=23409859;64:frequency=29494575;67:frequency=35075158;
 72:frequency=46819719;76:frequency=58989149;79:frequency=70150316;default:frequency=0;endcase
 endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s ons=%0d offs=%0d",why,ons,offs);end endtask
 task send(input [7:0] b);begin
  @(negedge clk);while(!dut.bluetooth_on.link.core.rx_ready)@(negedge clk);
  rb=b;rv=1;@(negedge clk);rv=0;
 end endtask
 task command(input [7:0] cmd,input [15:0] seq,input integer len);
 reg [15:0] crc;reg [7:0] b;integer before_reply,ticks;begin
  before_reply=replies;send(8'ha5);send(8'h5a);crc=16'hffff;
  for(integer k=0;k<6+len;k++)begin
   case(k)0:b=1;1:b=cmd;2:b=seq[7:0];3:b=seq[15:8];4:b=len;5:b=0;default:b=payload[k-6];endcase
   send(b);crc=crc16(crc,b);
  end
  send(crc[7:0]);send(crc[15:8]);ticks=0;
  while(replies==before_reply && ticks<100000)begin @(negedge clk);ticks++;end
  check(replies==before_reply+1 && response[8]==0,"actual framed command accepted");
 end endtask
 always @(posedge clk)if(!dut.bluetooth_on.source_reset && dut.bluetooth_on.link.core.tx_valid)begin
  response[rxn]=dut.bluetooth_on.link.core.tx_data;rxn++;
  if(rxn==8)goal=10+{response[7],response[6]};
  if(goal>0 && rxn==goal)begin replies++;rxn=0;goal=0;end
 end
 always @(posedge dut.audio_clk)begin
  if(dut.audio_reset || dut.bt_flush)begin
   logical_held=0;for(integer i=0;i<32;i++)begin phase[i]=0;physical_gain[i]=256;physical_pitch[i]=0;end
   for(integer i=0;i<16;i++)begin velocities[i]=127;pitches[i]=0;end
   expected_mix=0;terms=0;
  end else begin
   if(dut.note_valid && dut.note_ready)begin
    check(dut.take_bt && dut.note_id==dut.bluetooth_on.source_id,"identity survives CDC, bridge and actual top mux");
    check(dut.note_id<16,"automatic identity remains in0..15");
    if(dut.note_on)begin
     check(!logical_held[dut.note_id],"overlapping notes never share one logical identity");
     check(dut.bt_pitch==records[ons][39:32] && dut.bt_velocity==records[ons][47:40],"pitch/velocity preserve uploaded record order");
     logical_held[dut.note_id]=1;pitches[dut.note_id]=dut.bt_pitch;velocities[dut.note_id]=dut.bt_velocity;ons++;
    end else begin
     check(logical_held[dut.note_id],"Note Off releases its own live identity");
     logical_held[dut.note_id]=0;offs++;
    end
   end
   if(dut.sound.gain_valid)begin
    check($signed(dut.sound.gain_sample)==expected[terms],"each rendered voice has its own exact phase/envelope/velocity");terms++;
   end
   if(dut.sound.mix_valid)begin
    check(terms==32 && dut.sound.mix_sample===expected_mix,"mixed PCM equals the sum of32 independent contexts");
    if($signed(expected_mix)>peak)peak=$signed(expected_mix);
   end
   if(dut.frame_ce)begin
    terms=0;total=0;
    // Bind accepted logical metadata at each physical start. A reused logical
    // ID must never change an older voice's release-tail reference gain.
    for(integer v=0;v<32;v++)if(dut.sound.voice_start[v])begin
     physical_gain[v]=(velocities[dut.sound.voice_ids[v*7+:7]]*256+63)/127;
     physical_pitch[v]=pitches[dut.sound.voice_ids[v*7+:7]];
    end
    // Ownership is frozen during render. ADSR updates on this frame edge.
    #0.001;
    for(integer v=0;v<32;v++)begin
     phase_now=dut.sound.frame_restart[v]?0:phase[v];
     phase[v]=phase_now+dut.sound.frame_fcw[v*32+:32];
     term=dut.sound.voice_level[v];term=(term*dut.sound.startup_level)>>>16;
     if(dut.voice_active[v] || dut.voice_held[v])begin
      check(dut.sound.voice_gains[v*9+:9]==physical_gain[v] && dut.sound.voice_pitches[v*7+:7]==physical_pitch[v],"physical gain/pitch remain immutable through release and identity reuse");
      check(dut.sound.frame_fcw[v*32+:32]==frequency(physical_pitch[v]),"release tail retains its independently recorded frequency");
     end
     term=(term*physical_gain[v])>>>8;
     term=(term*$signed(wave[phase_now[31:20]]))>>>13;
     expected[v]=term;total=total+term;
    end
    total=total>>>8;expected_mix=total>32767?32767:total < -32768?-32768:total;
   end
  end
 end
 task group(input integer count,input integer cumulative);
 reg [15:0] seen;integer id;begin
  wait(ons==cumulative);repeat(2)begin @(posedge dut.audio_clk);while(!dut.frame_ce)@(posedge dut.audio_clk);end
  repeat(256)@(negedge dut.audio_clk);seen=0;
  for(integer v=0;v<32;v++)if(dut.voice_held[v])begin
   id=dut.sound.voice_ids[v*7+:7];check(id<16 && !seen[id],"each held physical voice has a distinct identity");seen[id]=1;
   check(dut.sound.voice_fcw[v*32+:32]==frequency(pitches[id]),"each physical voice retains the frequency of its own note");
  end
  check($countones(dut.voice_held)==count && seen==logical_held,"all simultaneous notes occupy independent physical voices");
  check(dut.lcd_on.display_driver.count_voices(dut.voice_held)==count,"display popcount retains the full physical voice count");
  check(dut.lcd_on.display_driver.pixel_status[11:6]==count && dut.lcd_on.display_driver.pixel_status[5:0]==$countones(dut.voice_active),"display HOLD counts held notes; ACTIVE independently includes native release tails");
  check(dut.bt_source_ids==logical_held && dut.bt_audio_ids==logical_held,"passive source/audio monitors agree with independent event scoreboard");
  check(dut.lcd_on.display_driver.pixel_more[97:82]==logical_held && dut.lcd_on.display_driver.pixel_more[113:98]==logical_held,
    "source and receiver identity masks reach more INFO atomically");
  check(dut.lcd_on.display_driver.pixel_more[145:114]==dut.voice_held,"physical held bitmap reaches more INFO unchanged");
  $display("IDENTITY_GROUP voices=%0d ids=%h ons=%0d",count,seen,ons);
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",directory))directory="reports/bt_identity";
  if(!$value$plusargs("IDENTITY_NOTES=%s",notes_file))notes_file="sim/data/bt_identity_notes.hex";
  $readmemh(notes_file,records);
  case(TIMBRE)
   1:$readmemh("src/rom/flute4096.hex",wave);2:$readmemh("src/rom/reed4096.hex",wave);
   3:$readmemh("src/rom/cello4096.hex",wave);4:$readmemh("src/rom/piano4096.hex",wave);
   5:$readmemh("src/rom/guitar4096.hex",wave);6:$readmemh("src/rom/vibraphone4096.hex",wave);
   default:$readmemh("src/rom/sine4096.hex",wave);
  endcase
  force dut.selected_timbre=3'(TIMBRE);
  force dut.bluetooth_on.link.core.rx_valid=rv;force dut.bluetooth_on.link.core.rx_data=rb;force dut.bluetooth_on.link.core.tx_ready=1'b1;
  #100 rst=0;wait(dut.input_ready);command(1,0,0);
  check(response[15]==16,"production HELLO exposes16 automatic identities");
  crc32=32'hffffffff;for(integer i=0;i<29;i++)for(integer b=0;b<8;b++)crc32=crc_byte(crc32,records[i]>>(8*b));crc32=~crc32;
  payload[0]=29;payload[1]=0;for(integer b=0;b<4;b++)payload[2+b]=crc32>>(8*b);command(8'h10,1,6);
  payload[0]=0;payload[1]=0;for(integer i=0;i<29;i++)for(integer b=0;b<8;b++)payload[2+i*8+b]=records[i]>>(8*b);
  command(8'h11,2,234);command(8'h12,3,0);command(8'h20,4,0);
  group(1,1);group(4,5);group(8,13);group(16,29);
  wait(offs==29);wait(!dut.bt_inhibit);check(!dut.gate && logical_held==0,"all29 identities are released at natural end");
  check(peak>0 && peak<32767,"polyphony produces bounded nonzero PCM");
  $display("PASS tb_bt_identity checks=%0d timbre=%0d ons=%0d offs=%0d peak=%0d",checks,TIMBRE,ons,offs,peak);$finish;
 end
 initial begin #30000000;$fatal(1,"identity regression timeout");end
endmodule
