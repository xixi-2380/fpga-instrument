package cn.whu.gaoshan.core;
import java.io.*;
import java.util.*;
/** Resumable frozen capture download, retained by the Activity on reconnect. */
public final class PerformanceRecording {
 public final long id,elapsed,crc;public final int count,reason;public final byte[] data;public int received;
 public PerformanceRecording(ProtocolClient.RecordingStatus s){if(s.state!=5||s.count<0||s.count>4096)throw new IllegalArgumentException("Recording is not frozen");id=s.id;elapsed=s.elapsed;crc=s.crc;count=s.count;reason=s.reason;data=new byte[count*12];}
 public boolean matches(ProtocolClient.RecordingStatus s){return s.state==5&&s.id==id&&s.count==count&&s.crc==crc&&s.elapsed==elapsed;}
 public void verify(){if(received!=count||Wire.crc32(data)!=crc)throw new IllegalArgumentException("Recording CRC/count mismatch");for(int i=0;i<data.length;i+=12){long start=Wire.u32(data,i),duration=Wire.u32(data,i+4);if(start>3600000||duration<1||duration>3600000||start+duration>3600001||(data[i+8]&255)<21||(data[i+8]&255)>108||(data[i+9]&255)<1||(data[i+9]&255)>127||(data[i+10]&255)>15||(data[i+11]&255)>35)throw new IllegalArgumentException("Invalid recording record "+i/12);}}
 private static void vlq(ByteArrayOutputStream b,long value){if(value<0||value>0xfffffff)throw new IllegalArgumentException("MIDI delta overflow");int v=(int)value,packed=v&127;while((v>>>=7)!=0)packed=(packed<<8)|((v&127)|128);for(;;){b.write(packed&255);if((packed&128)==0)break;packed>>>=8;}}
 private static void meta(ByteArrayOutputStream b,int type,byte[] bytes){b.write(255);b.write(type);vlq(b,bytes.length);b.write(bytes,0,bytes.length);}
 private static void track(DataOutputStream out,ByteArrayOutputStream bytes)throws IOException{out.writeInt(0x4d54726b);out.writeInt(bytes.size());bytes.writeTo(out);}
 public static final int[] GM={80,73,68,42,0,24,11,19,33,40,48,56,65,80,88,21};
 public byte[] midi()throws IOException{
  verify();ByteArrayOutputStream all=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(all);
  out.writeInt(0x4d546864);out.writeInt(6);out.writeShort(1);out.writeShort(37);out.writeShort(1000);
  ByteArrayOutputStream tempo=new ByteArrayOutputStream();vlq(tempo,0);meta(tempo,0x51,new byte[]{15,66,64});vlq(tempo,0);meta(tempo,0x2f,new byte[0]);track(out,tempo);
  for(int key=0;key<36;key++){
   ByteArrayOutputStream b=new ByteArrayOutputStream();int ch=key%15;if(ch>=9)ch++;
   vlq(b,0);meta(b,0x21,new byte[]{(byte)(key/15)});vlq(b,0);meta(b,3,("PCB "+(key/12+1)+" KEY "+(key%12+1)).getBytes("UTF-8"));
   long tick=0;List<long[]> events=new ArrayList<>();
   for(int i=0;i<data.length;i+=12)if((data[i+11]&255)==key){
    long start=Wire.u32(data,i),duration=Wire.u32(data,i+4);int pitch=data[i+8]&255,tone=data[i+10]&255;
    events.add(new long[]{start,1,i});events.add(new long[]{start+duration,0,i});
   }
   events.sort(Comparator.<long[]>comparingLong(e->e[0]).thenComparingLong(e->e[1]).thenComparingLong(e->e[2]));
   for(long[] event:events){int i=(int)event[2],pitch=data[i+8]&255,tone=data[i+10]&255;vlq(b,event[0]-tick);tick=event[0];
    if(event[1]==1){b.write(0xc0|ch);b.write(GM[tone]);vlq(b,0);meta(b,0x7f,new byte[]{'G','S','K','M',1,(byte)tone});vlq(b,0);b.write(0x90|ch);b.write(pitch);b.write(data[i+9]&255);}
    else{b.write(0x80|ch);b.write(pitch);b.write(0);}
   }
   vlq(b,0);meta(b,0x2f,new byte[0]);track(out,b);
  }
  return all.toByteArray();
 }
}
