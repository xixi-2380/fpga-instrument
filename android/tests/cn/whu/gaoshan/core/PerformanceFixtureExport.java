package cn.whu.gaoshan.core;
import java.nio.file.*;
public final class PerformanceFixtureExport {
 public static void main(String[] args)throws Exception{
  byte[] b=new byte[8*12];int[] pitches={60,60,64,67,72,69,65,60};int[] tones={0,9,4,5,1,15,10,4};int[] keys={0,15,1,2,35,16,3,0};int[] start={0,0,500,1000,1500,2000,2500,3000};
  for(int k=0;k<8;k++){int i=k*12;Wire.put32(b,i,start[k]);Wire.put32(b,i+4,450);b[i+8]=(byte)pitches[k];b[i+9]=100;b[i+10]=(byte)tones[k];b[i+11]=(byte)keys[k];}
  byte[] status=new byte[20];status[1]=5;Wire.put32(status,2,1);Wire.put16(status,6,8);Wire.put32(status,8,3500);Wire.put32(status,12,Wire.crc32(b));PerformanceRecording rec=new PerformanceRecording(new ProtocolClient.RecordingStatus(status));System.arraycopy(b,0,rec.data,0,b.length);rec.received=8;
  Files.write(Paths.get(args[0]),rec.midi());
 }
}
