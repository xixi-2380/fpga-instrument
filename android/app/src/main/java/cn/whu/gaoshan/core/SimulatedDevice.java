package cn.whu.gaoshan.core;
import java.io.*;
import java.util.*;

/** In-process reference peer for phone offline demonstration. Never claims FPGA success. */
public final class SimulatedDevice implements ProtocolClient.Transport {
    private final ArrayDeque<Integer> replies=new ArrayDeque<>();
    private final ByteArrayOutputStream store=new ByteArrayOutputStream();
    private byte[] cachedRequest,cachedResponse;private int expected=1,total=0,received=0,state=0,lastError=0;
    private long expectedCrc,duration=0,position=0,started=0;private boolean hello=false,valid=false,upload=false,closed=false;
    public int dataWrites=0,playStarts=0,dropCommand=-1,dropCount=0;
    private void update(){if(state==1){position=Math.min(duration,System.nanoTime()/1000000-started);if(position>=duration)state=0;}}
    private byte[] error(int code){lastError=code;return new byte[]{(byte)code};}
    private void clearUpload(){upload=false;total=0;received=0;position=0;store.reset();}
    private static byte[] ok(){return new byte[]{0};}
    private static byte[] index(int n){byte[] b={0,0,0};Wire.put16(b,1,n);return b;}
    private byte[] execute(int cmd,byte[] p){
        if(cmd!=0x10&&cmd!=0x11&&cmd!=0x12&&cmd!=0x13&&cmd!=0x20&&cmd!=0x21&&cmd!=0x22&&cmd!=0x23&&cmd!=0x30)return error(1);
        if((cmd==0x10&&p.length!=6)||(cmd==0x11&&(p.length<10||(p.length-2)%8!=0))||(cmd!=0x10&&cmd!=0x11&&p.length!=0))return error(3);
        if(!hello)return error(5);update();
        if(upload&&(cmd==0x10||cmd>=0x20&&cmd<=0x22))return error(5);
        if(cmd==0x10){if(state!=0)return error(5);int n=Wire.u16(p,0);if(n==0)return error(6);if(n>1024)return error(8);
            valid=false;upload=true;total=n;received=0;position=0;duration=0;expectedCrc=Wire.u32(p,2);store.reset();return index(0);}
        if(cmd==0x11){if(!upload)return error(5);int first=Wire.u16(p,0),n=(p.length-2)/8;if(first!=received)return error(7);if(received+n>total)return error(8);
            byte[] previous=store.toByteArray();long last=received==0?0:Wire.u32(previous,previous.length-8);
            for(int i=2;i<p.length;i+=8){long start=Wire.u32(p,i),end=start+Wire.u16(p,i+6);int note=p[i+4]&255,vel=p[i+5]&255;
                if(start<last||note<48||note>83||vel<1||vel>127||Wire.u16(p,i+6)==0||end>3600000)return error(6);last=start;}
            store.write(p,2,p.length-2);received+=n;dataWrites++;return index(received);}
        if(cmd==0x12){if(!upload||received!=total)return error(5);byte[] data=store.toByteArray();if(Wire.crc32(data)!=expectedCrc){valid=false;clearUpload();return error(9);}
            List<Score.Note> notes=new ArrayList<>();for(int i=0;i<data.length;i+=8)notes.add(new Score.Note(Wire.u32(data,i),data[i+4]&255,data[i+5]&255,Wire.u16(data,i+6)));
            Score s=new Score(notes,Collections.emptyList());if(s.polyphony>4){valid=false;clearUpload();return error(10);}
            duration=s.duration;upload=false;valid=true;position=0;byte[] b=new byte[5];Wire.put32(b,1,duration);return b;}
        if(cmd==0x13){if(upload){valid=false;clearUpload();}return ok();}
        if(cmd==0x23){state=0;position=0;return ok();}
        if(cmd==0x30){byte[] b=new byte[13];b[1]=(byte)(valid?1:0);b[2]=(byte)(upload?1:0);b[3]=(byte)state;Wire.put16(b,4,received);Wire.put16(b,6,total);Wire.put32(b,8,position);b[12]=(byte)lastError;return b;}
        if(!valid)return error(14);
        if(cmd==0x20){state=1;position=0;started=System.nanoTime()/1000000;playStarts++;}
        if(cmd==0x21){if(state==0)return error(5);state=2;}
        if(cmd==0x22){if(state==0)return error(5);if(state==2){state=1;started=System.nanoTime()/1000000-position;}}
        return ok();
    }
    public synchronized void write(byte[] request)throws IOException{
        if(closed)throw new IOException("模拟连接已关闭");Wire.Decoder d=new Wire.Decoder();Wire.Frame f=null;for(byte b:request)f=d.accept(b&255,0);
        if(f==null||f.cmd>=128)return;
        byte[] response;
        if(f.version!=1)response=Wire.frame(f.cmd|128,f.seq,new byte[]{2});
        else if(f.cmd==1){if(f.seq!=0||f.payload.length!=0)response=Wire.frame(129,f.seq,error(3));
            else {if(upload){valid=false;clearUpload();}hello=true;expected=1;cachedRequest=null;cachedResponse=null;lastError=0;
                byte[] b=new byte[20];b[1]=1;b[2]=1;Wire.put16(b,3,256);Wire.put16(b,5,1024);b[7]=4;b[8]=48;b[9]=83;Wire.put16(b,10,5);Wire.put32(b,12,9600);Wire.put32(b,16,3600000);response=Wire.frame(129,0,b);}}
        else if(cachedRequest!=null&&Arrays.equals(cachedRequest,request))response=cachedResponse;
        else if(f.seq!=expected)response=Wire.frame(f.cmd|128,f.seq,error(11));
        else {response=Wire.frame(f.cmd|128,f.seq,execute(f.cmd,f.payload));cachedRequest=request.clone();cachedResponse=response.clone();expected++;}
        if(f.cmd==dropCommand&&dropCount>0){dropCount--;return;}
        for(byte b:response)replies.add(b&255);
    }
    public synchronized int read(int timeoutMs)throws IOException{if(closed)throw new IOException("模拟连接已关闭");if(!replies.isEmpty())return replies.remove();try{wait(Math.min(timeoutMs,5));}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IOException("中断",e);}return -1;}
    public synchronized void drain(){replies.clear();}
    public synchronized void close(){closed=true;replies.clear();notifyAll();}
}
