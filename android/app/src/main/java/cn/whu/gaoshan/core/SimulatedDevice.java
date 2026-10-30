package cn.whu.gaoshan.core;
import java.io.*;
import java.util.*;

/** In-process reference peer for phone offline demonstration. Never claims FPGA success. */
public final class SimulatedDevice implements ProtocolClient.Transport {
    private final boolean extensions;
    private int format=0;private final int[] formats=new int[32];private int pendingFormat;
    private int stride(){return format==1?12:8;}
    private final byte[][] library=new byte[32][];private final byte[][] names=new byte[32][];
    private int jobId=0,jobOperation=0,jobIndex=0,jobState=0,polls=0;private long jobCrc=0;private byte[] pendingData,pendingName;
    public int libraryStarts=0;
    public SimulatedDevice(){this(false);}public SimulatedDevice(boolean extensions){this.extensions=extensions;}
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
    private KeyMap keyMap=KeyMap.defaults();private byte[] staged;private boolean[] stagedKeys;
    private long stageToken,stageCrc,captureId=0,recordStarted,mapSavedCrc;private int recordState=0,mapJob=0,mapVersion=0;
    private byte[] capture=new byte[0];
    private byte[] performanceCommand(int cmd,byte[] p){
        if(!hello)return error(5);
        if(recordState==1&&(cmd>=0x52&&cmd<=0x55||cmd==0x57||cmd==0x61))return error(5);
        if(cmd==0x50){if(p.length!=0)return error(3);byte[] b=new byte[12];b[1]=1;b[2]=36;b[3]=21;b[4]=108;b[5]=16;Wire.put16(b,6,4096);Wire.put32(b,8,3600000);return b;}
        if(cmd==0x51){if(p.length!=1)return error(3);int k=p[0]&255;if(k>=36)return error(6);return new byte[]{0,(byte)k,(byte)keyMap.pitch(k),(byte)keyMap.timbre(k)};}
        if(cmd==0x52){if(p.length!=8)return error(3);stageToken=Wire.u32(p,0);stageCrc=Wire.u32(p,4);staged=new byte[72];stagedKeys=new boolean[36];return ok();}
        if(cmd==0x53){if(p.length!=7)return error(3);int k=p[4]&255;if(staged==null||stageToken!=Wire.u32(p,0)||k>=36)return error(6);int pitch=p[5]&255,tone=p[6]&255;if(pitch<21||pitch>108||tone>15&&tone!=31)return error(6);staged[2*k]=p[5];staged[2*k+1]=p[6];stagedKeys[k]=true;return ok();}
        if(cmd==0x54){if(p.length!=4)return error(3);if(staged==null||stageToken!=Wire.u32(p,0))return error(6);for(boolean filled:stagedKeys)if(!filled)return error(6);if(Wire.crc32(staged)!=stageCrc)return error(9);if(upload||state!=0||jobState==1)return error(5);keyMap=new KeyMap(staged);staged=null;mapVersion++;return ok();}
        if(cmd==0x55){if(p.length!=4)return error(3);if(upload||state!=0||jobState==1)return error(5);if(Wire.u32(p,0)!=keyMap.crc())return error(6);mapSavedCrc=keyMap.crc();return index(++mapJob);}
        if(cmd==0x56){if(p.length!=0)return error(3);byte[] b=new byte[16];Wire.put16(b,1,mapJob);b[3]=(byte)(mapJob==0?0:2);Wire.put32(b,5,mapSavedCrc);b[9]=13;Wire.put16(b,10,mapVersion);Wire.put32(b,12,keyMap.crc());return b;}
        if(cmd==0x57){if(p.length!=0)return error(3);if(upload||state!=0||jobState==1)return error(5);keyMap=KeyMap.defaults();mapVersion++;return ok();}
        if(cmd==0x60||cmd==0x63){if(p.length!=0)return error(3);byte[] b=new byte[20];b[1]=(byte)recordState;Wire.put32(b,2,captureId);Wire.put16(b,6,capture.length/12);Wire.put32(b,8,recordState==0?0:recordState==1?Math.min(3600000,System.nanoTime()/1000000-recordStarted):1000);Wire.put32(b,12,Wire.crc32(capture));b[16]=(byte)(recordState==5?1:0);return b;}
        if(cmd==0x61){if(p.length!=0)return error(3);if(upload||state!=0||jobState==1)return error(5);captureId++;capture=new byte[0];recordStarted=System.nanoTime()/1000000;recordState=1;byte[] b=new byte[5];Wire.put32(b,1,captureId);return b;}
        if(cmd==0x62){if(p.length!=0)return error(3);if(recordState==0)return error(5);if(recordState==1){capture=new byte[24];for(int k=0;k<2;k++){int off=k*12;Wire.put32(capture,off,k*100);Wire.put32(capture,off+4,500);capture[off+8]=(byte)keyMap.pitch(k);capture[off+9]=100;capture[off+10]=(byte)(keyMap.timbre(k)==31?4:keyMap.timbre(k));capture[off+11]=(byte)k;}recordState=5;}return ok();}
        if(cmd==0x64){if(p.length!=6)return error(3);if(recordState!=5)return error(5);int k=Wire.u16(p,4);if(Wire.u32(p,0)!=captureId||k>=capture.length/12)return error(6);byte[] b=new byte[20];Wire.put32(b,1,captureId);Wire.put16(b,5,k);b[7]=1;System.arraycopy(capture,k*12,b,8,12);return b;}
        if(cmd==0x65){if(p.length!=4)return error(3);if(recordState==1)return error(5);if(Wire.u32(p,0)!=captureId)return error(6);capture=new byte[0];recordState=0;return ok();}
        if(cmd==0x66){if(p.length!=0)return error(3);byte[] b=new byte[8];b[1]=1;Wire.put16(b,2,4096);Wire.put32(b,4,3600000);return b;}
        return error(1);
    }
    private byte[] execute(int cmd,byte[] p){
        if(extensions&&cmd>=0x50&&cmd<=0x66)return performanceCommand(cmd,p);
        if(recordState==1&&(cmd==0x10||cmd==0x14||cmd>=0x20&&cmd<=0x22||cmd>=0x42&&cmd<=0x44))return error(5);
        if(extensions&&cmd==0x46)return p.length==0?new byte[]{0,3,26,21,108,35,59,0}:error(3);
        if(cmd==0x14&&!extensions)return error(1);
        if(extensions&&cmd>=0x40&&cmd<=0x45)return libraryCommand(cmd,p);
        if(extensions&&jobState==1&&(cmd==0x14||cmd==0x10||cmd>=0x20&&cmd<=0x23))return error(5);
        if(cmd!=0x14&&cmd!=0x10&&cmd!=0x11&&cmd!=0x12&&cmd!=0x13&&cmd!=0x20&&cmd!=0x21&&cmd!=0x22&&cmd!=0x23&&cmd!=0x30)return error(1);
        if((cmd==0x10&&p.length!=6)||(cmd==0x14&&p.length!=7)||(cmd==0x11&&(p.length<10||(p.length-2)%stride()!=0))||(cmd!=0x14&&cmd!=0x10&&cmd!=0x11&&p.length!=0))return error(3);
        if(!hello)return error(5);update();
        if(upload&&(cmd==0x10||cmd==0x14||cmd>=0x20&&cmd<=0x22))return error(5);
        if(cmd==0x10||cmd==0x14){if(cmd==0x14&&p[6]!=1)return error(6);if(state!=0)return error(5);int n=Wire.u16(p,0);if(n==0)return error(6);if(n>(extensions?4096:1024))return error(8);
            format=cmd==0x14?1:0;valid=false;upload=true;total=n;received=0;position=0;duration=0;expectedCrc=Wire.u32(p,2);store.reset();return index(0);}
        if(cmd==0x11){if(!upload)return error(5);int first=Wire.u16(p,0),n=(p.length-2)/stride();if(first!=received)return error(7);if(received+n>total)return error(8);
            byte[] previous=store.toByteArray();long last=received==0?0:Wire.u32(previous,previous.length-stride());
            for(int i=2;i<p.length;i+=stride()){long start=Wire.u32(p,i),end=start+Wire.u16(p,i+6);int note=p[i+4]&255,vel=p[i+5]&255;
                if(start<last||note<(extensions?21:48)||note>(extensions?108:83)||vel<1||vel>127||Wire.u16(p,i+6)==0||end>3600000)return error(6);if(format==1){int t=p[i+8]&255,ch=p[i+9]&255;if(t>25||ch>15||p[i+10]!=0||p[i+11]!=0||(t>=16)!=(ch==9))return error(6);if(t>=16){try{if(Timbres.drum(note)!=t||Wire.u16(p,i+6)!=Timbres.DRUM_MS[t-16])return error(6);}catch(IllegalArgumentException e){return error(6);}}}last=start;}
            store.write(p,2,p.length-2);received+=n;dataWrites++;return index(received);}
        if(cmd==0x12){if(!upload||received!=total)return error(5);byte[] data=store.toByteArray();if(Wire.crc32(data)!=expectedCrc){valid=false;clearUpload();return error(9);}
            List<Score.Note> notes=new ArrayList<>();for(int i=0;i<data.length;i+=stride())notes.add(format==0?new Score.Note(Wire.u32(data,i),data[i+4]&255,data[i+5]&255,Wire.u16(data,i+6)):new Score.Note(Wire.u32(data,i),data[i+4]&255,data[i+5]&255,Wire.u16(data,i+6),data[i+8]&255,data[i+9]&255));
            Score s=new Score(notes,Collections.emptyList());if(s.polyphony>(extensions?16:4)){valid=false;clearUpload();return error(10);}
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
                byte[] b=new byte[20];b[1]=1;b[2]=1;Wire.put16(b,3,256);Wire.put16(b,5,extensions?4096:1024);b[7]=(byte)(extensions?16:4);b[8]=(byte)(extensions?21:48);b[9]=(byte)(extensions?108:83);Wire.put16(b,10,5);Wire.put32(b,12,9600);Wire.put32(b,16,3600000);response=Wire.frame(129,0,b);}}
        else if(cachedRequest!=null&&Arrays.equals(cachedRequest,request))response=cachedResponse;
        else if(f.seq!=expected)response=Wire.frame(f.cmd|128,f.seq,error(11));
        else {response=Wire.frame(f.cmd|128,f.seq,execute(f.cmd,f.payload));cachedRequest=request.clone();cachedResponse=response.clone();expected++;}
        if(f.cmd==dropCommand&&dropCount>0){dropCount--;return;}
        for(byte b:response)replies.add(b&255);
    }
    private static long recordDuration(byte[] data,int fmt){long max=0;for(int i=0;i<data.length;i+=(fmt==1?12:8))max=Math.max(max,Wire.u32(data,i)+Wire.u16(data,i+6));return max;}
    private byte[] libraryCommand(int cmd,byte[] p){
        if(!hello)return error(5);
        if((cmd==0x40&&p.length!=0)||(cmd==0x41&&p.length!=1)||(cmd==0x42&&p.length!=8)||((cmd==0x43||cmd==0x44)&&p.length!=1)||(cmd==0x45&&p.length!=8))return error(3);
        byte[] b=new byte[20];
        if(cmd==0x40){b[1]=1;b[2]=31;b[3]=32;Wire.put16(b,4,4096);b[6]=16;b[7]=0x18;b[8]=0x40;b[9]=(byte)0xef;Wire.put16(b,13,jobId);Wire.put32(b,16,expectedCrc);return b;}
        if(cmd==0x45){
            if(jobState==0||Wire.u16(p,0)!=jobId||(p[2]&255)!=jobOperation||(p[3]&255)!=jobIndex||Wire.u32(p,4)!=jobCrc)return error(0x28);
            if(jobState==1&&++polls>=2){
                if(jobOperation==0){library[jobIndex]=pendingData;formats[jobIndex]=pendingFormat;names[jobIndex]=pendingName;}
                else if(jobOperation==1){byte[] song=library[jobIndex];store.reset();store.write(song,0,song.length);format=formats[jobIndex];received=total=song.length/stride();duration=recordDuration(song,format);expectedCrc=Wire.crc32(song);valid=true;position=0;}
                else{library[jobIndex]=null;names[jobIndex]=null;}jobState=2;
            }
            Wire.put16(b,1,jobId);b[3]=(byte)jobState;b[5]=(byte)jobOperation;b[6]=(byte)jobIndex;Wire.put32(b,7,jobCrc);b[11]=(byte)(jobState==2&&jobOperation==0?1:0);return b;
        }
        int index=p[0]&255;if(index>=32)return error(6);
        if(cmd==0x41){b[1]=(byte)index;if(library[index]!=null){byte[] song=library[index];b[2]=1;Wire.put16(b,3,song.length/(formats[index]==1?12:8));Wire.put32(b,5,recordDuration(song,formats[index]));Wire.put32(b,9,Wire.crc32(song));System.arraycopy(names[index],0,b,13,7);}return b;}
        if(jobState==1||upload||state!=0)return error(5);
        if(cmd==0x42&&!valid||cmd!=0x42&&library[index]==null)return error(14);
        jobOperation=cmd-0x42;jobIndex=index;jobCrc=jobOperation==0?expectedCrc:0;jobId=(jobId+1)&65535;jobState=1;polls=0;libraryStarts++;
        if(jobOperation==0){pendingFormat=format;pendingData=store.toByteArray();pendingName=Arrays.copyOfRange(p,1,8);if(pendingName[0]==0){String name=String.format(Locale.ROOT,"S%03d",index+1);for(int i=0;i<name.length();i++)pendingName[i]=(byte)name.charAt(i);}}
        return index(jobId);
    }
    /** Mock power loss only: persisted model directory survives, volatile RAM/jobs do not. */
    public synchronized void powerCycle(){hello=false;valid=false;upload=false;state=0;position=0;total=received=0;store.reset();cachedRequest=cachedResponse=null;replies.clear();expected=1;jobState=0;closed=false;}
    public synchronized int read(int timeoutMs)throws IOException{if(closed)throw new IOException("模拟连接已关闭");if(!replies.isEmpty())return replies.remove();try{wait(Math.min(timeoutMs,5));}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IOException("中断",e);}return -1;}
    public synchronized void drain(){replies.clear();}
    public synchronized void close(){closed=true;replies.clear();notifyAll();}
}
