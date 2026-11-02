package cn.whu.gaoshan.core;
import java.nio.file.*;import java.util.*;import java.util.concurrent.atomic.AtomicBoolean;
import static cn.whu.gaoshan.core.CoreTests.*;
public final class PercussionTests {
 public static void main(String[] args)throws Exception{
  int before=checks;List<byte[]> events=new ArrayList<>();
  int[] prior={35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,55,57,59};
  // Every previously supported key retains the exact canonical key and bytes.
  for(int key:prior){
   check(Timbres.drumKey(key)==key,"old drum key stable "+key);
   MidiFile m=new MidiFile(smf(0,480,track(event(0,0x99,key,100),event(1,0x89,key,0),end())));
   Score s=m.convert(-1,-1,0,-1,false);
   Score expected=new Score(Arrays.asList(new Score.Note(0,key,100,Timbres.DRUM_MS[Timbres.drum(key)-16],Timbres.drum(key),9)),Collections.emptyList());
   check(Arrays.equals(s.bytes(),expected.bytes()),"old drum record exact "+key);
  }
  for(int key=35;key<=81;key++){
   int mapped=Timbres.drumKey(key);check(mapped>=35&&mapped<=59,"wire key fits old firmware "+key);
   check(Timbres.drum(mapped)>=16&&Timbres.drum(mapped)<=25,"stable drum ID "+key);
   events.add(event(key==35?0:1920,0x99,key,100)); // Deliberately no Offs.
  }
  events.add(end());byte[] all=smf(0,480,track(events.toArray(new byte[0][])));
  Score palette=new MidiFile(all).convert(-1,-1,48,-1,false);
  check(palette.notes.size()==47,"all GM1 keys accepted without Off");
  for(int i=0;i<47;i++){
   Score.Note n=palette.notes.get(i);int key=35+i;
   check(n.pitch==Timbres.drumKey(key)&&n.timbre==Timbres.drum(n.pitch)&&n.channel==9,"all canonical records "+key);
   check(n.duration==Timbres.DRUM_MS[n.timbre-16],"fixed one shot duration "+key);
  }
  check(palette.warnings.stream().anyMatch(w->w.contains("10种鼓音近似")),"approximation disclosed");
  MidiFile one=new MidiFile(smf(0,480,track(event(0,0x99,52,100),end())));
  Score plain=one.convert(-1,-1,0,-1,false),gong=one.convert(-1,-1,0,-1,false,true);
  check(plain.notes.size()==1&&plain.notes.get(0).timbre==24,"GM52 remains original cymbal by default");
  check(gong.notes.size()==2&&gong.polyphony==2&&gong.duration==1500,"explicit gong uses exactly two existing voices");
  check(gong.notes.get(0).pitch==52&&gong.notes.get(1).pitch==41&&gong.notes.get(1).velocity==50,"gong layers are compatible cymbal and half-level low tom");
  check(gong.warnings.stream().anyMatch(w->w.contains("GM1无专用锣键")),"gong not mislabeled GM standard");
  MidiFile mixed=new MidiFile(smf(0,480,track(event(0,0xc0,40),event(0,0x90,60,100),event(0,0x99,52,90),event(480,0x80,60,0),event(0,0x89,52,0),end())));
  Score m=mixed.convert(-1,-1,12,11,false,true);
  check(m.notes.size()==3&&m.notes.get(0).pitch==72&&m.notes.get(0).timbre==11,"melody override transpose unaffected by percussion");
  check(mixed.convert(-1,-1,0,-1,true,true).notes.size()==1,"exclude drums also removes both gong layers");
  check(mixed.convert(-1,0,0,-1,false,true).notes.size()==1,"channel filtering removes percussion");
  check(mixed.convert(-1,9,0,-1,false,true).notes.size()==2,"percussion channel filter retains gong layers");
  rejects(()->one.convert(-1,-1,0,-2,false,true),"old protocol cannot encode gong layering");
  rejects(()->Timbres.drumKey(34),"GM lower bound");rejects(()->Timbres.drumKey(82),"GM upper bound");
  rejects(()->new Score.Note(0,54,100,80,19,9),"wire validator still rejects noncanonical new key");
  rejects(()->new MidiFile(smf(0,480,track(event(0,0x90,60,100),end()))).convert(-1,-1,0,-1,false),"melodic missing Off remains error");
  rejects(()->new MidiFile(smf(0,480,track(event(0,0x80,60,0),end()))).convert(-1,-1,0,-1,false),"melodic orphan Off remains error");
  Score repeated=new MidiFile(smf(0,480,track(event(0,0x99,52,100),event(0,0x99,52,127),event(1,0x89,52,0),end()))).convert(-1,-1,0,-1,false,true);
  check(repeated.notes.size()==4&&repeated.polyphony==4,"repeated same-key On and short Off preserve both hits");
  Score zero=new MidiFile(smf(0,480,track(event(0,0xb9,7,0),event(0,0x99,52,100),event(0,0xb9,7,127),event(0,0x90,60,100),event(480,0x80,60,0),end()))).convert(-1,-1,0,-1,false,true);
  check(zero.notes.size()==1,"zero CC7 suppresses both gong components");
  SimulatedDevice dev=new SimulatedDevice(true);ProtocolClient c=new ProtocolClient(dev,()->System.nanoTime()/1000000L,10);
  ProtocolClient.Capabilities caps=c.hello();check(c.audioCapabilities(),"same old capability handshake");palette.validate(caps);
  c.upload(palette,new AtomicBoolean(),(n,t)->{});check(c.status().total==47,"full palette uploads using existing protocol");
  c.upload(gong,new AtomicBoolean(),(n,t)->{});check(c.status().total==2,"gong uploads using old drum IDs");
  ProtocolClient.LibraryJob job=c.startLibraryJob(0,0,"PERC",Wire.crc32(gong.bytes()));c.libraryJob(job);check(c.libraryJob(job).state==2,"layered gong saves");dev.powerCycle();c.hello();c.audioCapabilities();job=c.startLibraryJob(1,0,"",0);c.libraryJob(job);check(c.libraryJob(job).state==2&&c.status().total==2,"layered gong survives library reset/load");
  List<Score.Note> crowded=new ArrayList<>();for(int k=0;k<9;k++)crowded.addAll(gong.notes);
  rejects(()->new Score(crowded,Collections.emptyList()).validate(caps),"gong extra voices count against negotiated16");
  Score sixteen=new Score(crowded.subList(0,16),Collections.emptyList());sixteen.validate(caps);check(sixteen.polyphony==16,"eight layered gong hits fit the16 automatic voices");
  if(args.length>0){
   Path dir=Paths.get(args[0]);Files.createDirectories(dir);Files.write(dir.resolve("gm1_percussion_47.mid"),all);
   byte[] demo=smf(0,480,track(event(0,0x99,36,100),event(480,0x99,38,100),event(480,0x99,42,100),event(480,0x99,49,100),event(1920,0x99,52,100),end()));
   Files.write(dir.resolve("gm1_drums_china52.mid"),demo);
   Score converted=new MidiFile(demo).convert(-1,-1,0,-1,false,true);byte[] bytes=converted.bytes();
   check(Arrays.equals(converted.bytes(),Score.percussionExample(true).bytes()),"App direct layered demo matches imported MIDI");
   check(Arrays.equals(new MidiFile(demo).convert(-1,-1,0,-1,false).bytes(),Score.percussionExample(false).bytes()),"App direct default demo matches imported MIDI");
   StringBuilder hex=new StringBuilder();for(byte b:bytes)hex.append(String.format(Locale.ROOT,"%02x%n",b&255));Files.write(dir.resolve("drums_gong_records.hex"),hex.toString().getBytes("US-ASCII"));
   StringBuilder packed=new StringBuilder();for(int i=0;i<bytes.length;i+=12){for(int k=11;k>=0;k--)packed.append(String.format(Locale.ROOT,"%02x",bytes[i+k]&255));packed.append('\n');}Files.write(dir.resolve("drums_gong_records96.hex"),packed.toString().getBytes("US-ASCII"));
   System.out.println("fixture notes="+converted.notes.size()+" polyphony="+converted.polyphony+" duration="+converted.duration+" crc="+Long.toHexString(Wire.crc32(bytes)));
  }
  System.out.println("PASS Percussion: "+(checks-before)+" checks; software model only");
 }
}
