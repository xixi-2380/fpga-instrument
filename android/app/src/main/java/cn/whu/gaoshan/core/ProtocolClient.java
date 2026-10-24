package cn.whu.gaoshan.core;
import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** One caller/worker only, stop-and-wait. No Android dependency. */
public final class ProtocolClient {
    public interface Transport extends Closeable {
        void write(byte[] data)throws IOException;
        int read(int timeoutMs)throws IOException; // -1 = timeout, EOF throws
        void drain()throws IOException;
    }
    public interface Progress {void confirmed(int notes,int total);}
    public interface Clock {long ms();}
    public static final class DeviceError extends IOException {
        public final int code;
        DeviceError(int code){super("设备错误 0x"+Integer.toHexString(code)+"："+errorText(code));this.code=code;}
    }
    public static final class Capabilities {
        public final int maxNotes,voices,minNote,maxNote,features,maxPayload;public final long baud,maxSongMs;
        public Capabilities(int maxNotes,int voices,int minNote,int maxNote,int features,long baud,long maxSongMs){
            this.maxNotes=maxNotes;this.voices=voices;this.minNote=minNote;this.maxNote=maxNote;this.features=features;this.baud=baud;this.maxSongMs=maxSongMs;this.maxPayload=256;
        }
        static Capabilities parse(byte[] b)throws IOException{
            if(b.length!=20||b[1]!=1||b[2]!=1||Wire.u16(b,3)!=256)throw new IOException("HELLO版本或载荷长度不符合v1");
            int n=Wire.u16(b,5),v=b[7]&255,lo=b[8]&255,hi=b[9]&255,f=Wire.u16(b,10);
            long baud=Wire.u32(b,12),ms=Wire.u32(b,16);
            if(n<1||v<1||lo>hi||hi>127||ms<1||(f&1)==0||(f&~7)!=0||(((f&4)!=0)!=(v>1))||(baud!=9600&&baud!=115200))throw new IOException("设备能力字段非法");
            return new Capabilities(n,v,lo,hi,f,baud,ms);
        }
    }
    public static final class Status {
        public final boolean songValid,uploading;public final int state,received,total,lastError;public final long position;
        Status(byte[] b)throws IOException{
            if(b.length!=13||(b[1]&255)>1||(b[2]&255)>1||(b[3]&255)>2)throw new IOException("状态响应结构错误");
            songValid=b[1]!=0;uploading=b[2]!=0;state=b[3]&255;received=Wire.u16(b,4);total=Wire.u16(b,6);position=Wire.u32(b,8);lastError=b[12]&255;
        }
    }
    private final Transport link;private final Clock clock;private final int timeoutMs;
    private final Wire.Decoder decoder=new Wire.Decoder();private int seq=1;private boolean session=false;
    private Capabilities capabilities;private long lastStatus=-1;
    public ProtocolClient(Transport link){this(link,()->System.nanoTime()/1000000L,2000);}
    public ProtocolClient(Transport link,Clock clock,int timeoutMs){this.link=link;this.clock=clock;this.timeoutMs=timeoutMs;}
    public boolean sessionReady(){return session;}
    public Capabilities hello()throws IOException{
        session=false;seq=1;capabilities=null;lastStatus=-1;decoder.reset();link.drain();
        byte[] b=exchange(1,0,new byte[0],20);capabilities=Capabilities.parse(b);session=true;return capabilities;
    }
    private byte[] exchange(int cmd,int id,byte[] payload,int successLength)throws IOException{
        byte[] request=Wire.frame(cmd,id,payload);
        for(int attempt=0;attempt<4;attempt++){
            link.write(request);long deadline=clock.ms()+timeoutMs;
            while(clock.ms()<deadline){
                int n=link.read((int)Math.min(200,Math.max(1,deadline-clock.ms())));
                if(n<0)continue;
                Wire.Frame f=decoder.accept(n,clock.ms());
                if(f==null||f.version!=1||f.cmd!=(cmd|128)||f.seq!=id)continue;
                if(f.payload.length<1)continue;
                int status=f.payload[0]&255;
                if(status!=0){if(f.payload.length!=1)continue;throw new DeviceError(status);}
                if(f.payload.length!=successLength)continue;
                return f.payload;
            }
        }
        throw new IOException("响应超时，已发送4次相同请求；若模块仍已连接，请重新验证FPGA通信；若链路断开，请重连。未完成上传需重新开始。");
    }
    private byte[] request(int cmd,byte[] payload,int expected)throws IOException{
        if(!session)throw new IOException("请先连接并完成HELLO");
        if(seq>65535){session=false;throw new IOException("序号已用尽，请重新HELLO");}
        int id=seq;
        try{byte[] b=exchange(cmd,id,payload,expected);seq++;return b;}
        catch(DeviceError e){if(e.code==0x0b||e.code==2||e.code==0x0d)session=false;else seq++;throw e;}
        catch(IOException e){session=false;throw e;}
    }
    public void command(int cmd)throws IOException{
        if(cmd<0x20||cmd>0x23)throw new IllegalArgumentException("invalid playback command");request(cmd,new byte[0],1);
    }
    public Status status()throws IOException{
        long now=clock.ms(),delay=lastStatus<0?0:500-(now-lastStatus);
        if(delay>0)try{Thread.sleep(delay);}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IOException("状态查询中断",e);}
        lastStatus=clock.ms();return new Status(request(0x30,new byte[0],13));
    }
    public long upload(Score score,AtomicBoolean cancel,Progress progress)throws IOException{
        if(capabilities==null||!session)throw new IOException("尚未握手");score.validate(capabilities);
        if(cancel.get())throw new IOException("上传已取消");
        Status current=status();if(current.uploading)throw new IOException("设备正在上传，请重新HELLO清理后再试");
        command(0x23); // STOP is always valid; pause/play must stop before BEGIN.
        byte[] records=score.bytes(),begin=new byte[6];Wire.put16(begin,0,score.notes.size());Wire.put32(begin,2,Wire.crc32(records));
        boolean begun=false;
        try{
            byte[] ack=request(0x10,begin,3);begun=true;
            if(Wire.u16(ack,1)!=0)throw new IOException("BEGIN确认索引不是0");progress.confirmed(0,score.notes.size());
            int count=score.notes.size();
            for(int index=0;index<count;){
                if(cancel.get()){request(0x13,new byte[0],1);begun=false;throw new IOException("上传已取消，设备已确认ABORT");}
                int n=Math.min(16,count-index);byte[] payload=new byte[2+8*n];Wire.put16(payload,0,index);System.arraycopy(records,index*8,payload,2,n*8);
                ack=request(0x11,payload,3);
                if(Wire.u16(ack,1)!=index+n)throw new IOException("DATA确认索引不一致");index+=n;progress.confirmed(index,count);
            }
            if(cancel.get()){request(0x13,new byte[0],1);begun=false;throw new IOException("上传已取消，设备已确认ABORT");}
            ack=request(0x12,new byte[0],5);begun=false;long duration=Wire.u32(ack,1);
            if(duration!=score.duration){session=false;throw new IOException("COMMIT时长与手机不一致，会话已作废，请重连检查");}
            return duration;
        }catch(IOException e){
            if(begun&&session){try{request(0x13,new byte[0],1);}catch(IOException cleanup){e.addSuppressed(cleanup);}}
            throw e;
        }
    }
    public void close(){session=false;try{link.close();}catch(IOException ignored){}}
    public static String errorText(int code){
        switch(code){case 1:return "未知命令";case 2:return "协议版本错误";case 3:return "载荷长度错误";case 5:return "状态不允许";case 6:return "参数或音符非法";case 7:return "上传索引错误";case 8:return "容量不足";case 9:return "整曲CRC错误";case 10:return "整曲声部等约束不满足";case 11:return "序号冲突，需要重新HELLO";case 12:return "上传事务超时";case 13:return "内部错误";case 14:return "没有有效曲谱";default:return "未定义错误";}
    }
}
