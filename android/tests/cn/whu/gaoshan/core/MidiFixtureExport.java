package cn.whu.gaoshan.core;
import java.nio.file.*;import java.util.*;
public final class MidiFixtureExport {
 public static void main(String[] a)throws Exception{
  byte[] b=Files.readAllBytes(Paths.get(a[0]));Score s=new MidiFile(b).convert(-1,-1,0,-1,false);s.validate(new ProtocolClient.Capabilities(4096,16,21,108,5,9600,3600000));byte[] data=s.bytes();StringBuilder text=new StringBuilder();for(byte x:data)text.append(String.format(Locale.ROOT,"%02x%n",x&255));Files.write(Paths.get(a[1]),text.toString().getBytes("US-ASCII"));System.out.println("notes="+s.notes.size()+" polyphony="+s.polyphony+" duration="+s.duration+" crc="+Long.toHexString(Wire.crc32(data)));
 }
}
