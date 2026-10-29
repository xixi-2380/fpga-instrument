package cn.whu.gaoshan.core;
import java.util.*;import java.util.concurrent.atomic.AtomicBoolean;import static cn.whu.gaoshan.core.CoreTests.*;
public final class MidiTimbreTests {
 public static void main(String[] args)throws Exception{
  int before=checks;
  for(int p=0;p<128;p++)check(Timbres.program(p)>=0&&Timbres.program(p)<16,"all GM programs mapped");
  MidiFile f=new MidiFile(smf(1,480,
   track(event(0,0xc0,40),event(0,0xb0,64,127),event(480,0xc0,32),event(480,0xb0,64,0),end()),
   track(event(0,0x90,60,100),event(240,0x80,60,0),event(240,0x90,60,90),event(240,0x80,60,0),end())));
  Score s=f.convert(1,0,0,-1,false);check(s.format==1&&s.bytes().length==24,"extended records");
  check(s.notes.get(0).timbre==9&&s.notes.get(1).timbre==8,"program follows channel across tracks and snapshots On");
  check(s.notes.get(0).duration==1000&&s.notes.get(1).duration==500,"pedal extends to release without changing onset timbre");
  check(f.convert(1,0,0,11,false).notes.get(0).timbre==11,"uniform melody override");
  MidiFile drums=new MidiFile(smf(0,480,track(event(0,0x99,36,100),event(1,0x89,36,0),event(0,0x90,21,100),event(480,0x80,21,0),end())));
  Score d=drums.convert(-1,-1,12,-1,false);check(d.notes.get(0).pitch==36&&d.notes.get(0).timbre==16&&d.notes.get(0).duration==250,"drum ignores transpose and short Note Off");check(d.notes.get(1).pitch==33,"melody transposes");
  rejects(()->new MidiFile(smf(0,480,track(event(0,0x99,54,100),event(1,0x89,54,0),end()))).convert(-1,-1,0,-1,false),"unsupported percussion explicit");
  MidiFile mute=new MidiFile(smf(0,480,track(event(0,0xb0,7,0),event(0,0x90,60,127),event(480,0x80,60,0),event(0,0xb0,7,127),event(0,0x90,61,127),event(480,0x80,61,0),end())));
  check(mute.convert(-1,-1,0,-1,false).notes.size()==1,"zero volume removes only silent records");
  MidiFile endPedal=new MidiFile(smf(0,480,track(event(0,0xb0,64,127),event(0,0x90,60,100),event(240,0x80,60,0),event(240,255,47,0))));
  check(endPedal.convert(-1,-1,0,-1,false).duration==500,"unreleased pedal closes at EOT");
  SimulatedDevice dev=new SimulatedDevice(true);ProtocolClient c=new ProtocolClient(dev,()->System.nanoTime()/1000000L,10);ProtocolClient.Capabilities caps=c.hello();check(c.audioCapabilities(),"capability negotiated");
  List<Score.Note> many=new ArrayList<>();for(int i=0;i<4096;i++)many.add(new Score.Note(i*2, i%2==0?21:108,100,1,i%16,0));
  Score full=new Score(many,Collections.emptyList());full.validate(caps);dev.dropCommand=0x14;dev.dropCount=1;c.upload(full,new AtomicBoolean(),(n,total)->{});check(dev.dataWrites==256,"4096 notes in 16-record packets with BEGIN retry dedup");
  ProtocolClient.LibraryJob job=c.startLibraryJob(0,0,"TIMBRE",Wire.crc32(full.bytes()));c.libraryJob(job);check(c.libraryJob(job).state==2,"save new format");dev.powerCycle();c.hello();c.audioCapabilities();job=c.startLibraryJob(1,0,"",0);c.libraryJob(job);check(c.libraryJob(job).state==2&&c.status().total==4096,"format and CRC survive library reboot");
  ProtocolClient old=new ProtocolClient(new SimulatedDevice(),()->System.nanoTime()/1000000L,10);old.hello();check(!old.audioCapabilities(),"old peer fallback");rejects(()->old.upload(s,new AtomicBoolean(),(n,total)->{}),"old peer cannot silently discard timbres");
  System.out.println("PASS MIDI timbres: "+(checks-before)+" checks; software model only");
 }
}
