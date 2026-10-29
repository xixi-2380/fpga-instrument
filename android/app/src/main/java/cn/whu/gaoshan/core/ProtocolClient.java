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
    public static final class LibraryCapabilities {
        public final boolean initialized,supported,writable;public final int entries,voices,status1,status2,status3,lastError,latestJobId;public final long jedecId,activeCrc;
        LibraryCapabilities(byte[] b)throws IOException{
            if(b.length!=20||b[1]!=1||(b[2]&0xe0)!=0||(b[3]&255)!=32||Wire.u16(b,4)!=4096||(b[6]&255)!=16)throw new IOException("曲库扩展能力不兼容");
            initialized=(b[2]&1)!=0;supported=(b[2]&2)!=0;writable=(b[2]&4)!=0;entries=b[3]&255;voices=b[6]&255;
            jedecId=(b[7]&255L)|((b[8]&255L)<<8)|((b[9]&255L)<<16);status1=b[10]&255;status2=b[11]&255;status3=b[12]&255;lastError=b[15]&255;latestJobId=Wire.u16(b,13);activeCrc=Wire.u32(b,16);
        }
    }
    public static String flashDiagnostic(LibraryCapabilities c){
        if(c==null)return "旧版RAM固件，不支持Flash曲库诊断";
        String reason=!c.initialized?"曲库尚未初始化":!c.supported?"未识别到有效Flash":
            (c.status1&1)!=0?"Flash正在擦写":
            c.writable?"允许标准SPI写入；芯片保护保持，成功以读回校验为准":"设备未开放写入，需核对固件";
        return String.format(Locale.ROOT,"Flash ID=%06X SR1=%02X SR2=%02X SR3=%02X\nINIT=%d SUPPORTED=%d WRITE=%d JOB=%04X ERROR=%02X CRC=%08X\n%s",
            c.jedecId,c.status1,c.status2,c.status3,c.initialized?1:0,c.supported?1:0,c.writable?1:0,c.latestJobId,c.lastError,c.activeCrc,reason);
    }
    public static String flashJobError(int code){
        return String.format(Locale.ROOT,"0x%02X：%s",code,code==9?"Flash读回校验失败（曲谱或目录）":errorText(code));
    }
    public static final class LibraryEntry {
        public final int index,count;public final boolean exists;public final long duration,crc;public final String name;
        LibraryEntry(byte[] b)throws IOException{
            if(b.length!=20||(b[1]&255)>=32||(b[2]&255)>1)throw new IOException("曲目元数据非法");
            index=b[1]&255;exists=b[2]!=0;count=Wire.u16(b,3);duration=Wire.u32(b,5);crc=Wire.u32(b,9);
            StringBuilder text=new StringBuilder();for(int i=13;i<20;i++){int ch=b[i]&255;if(ch==0)break;if(ch<32||ch>126)throw new IOException("曲名不是ASCII");text.append((char)ch);}name=text.toString();
            if(exists&&(count<1||count>4096||duration<1||duration>3600000))throw new IOException("曲目容量/时长非法");
        }
    }
    /** Includes an operation/slot/CRC fingerprint, not only a reused job number. */
    public static final class LibraryJob {
        public final int id,operation,index;public final long crc;
        public LibraryJob(int id,int operation,int index,long crc){
            if(id<0||id>65535||operation<0||operation>2||index<0||index>=32||crc<0||crc>0xffffffffL)throw new IllegalArgumentException("invalid library job");
            this.id=id;this.operation=operation;this.index=index;this.crc=crc;
        }
        byte[] token(){byte[] p=new byte[8];Wire.put16(p,0,id);p[2]=(byte)operation;p[3]=(byte)index;Wire.put32(p,4,crc);return p;}
    }
    public static final class LibraryJobStatus {
        public final int state,error;public final boolean persisted;
        LibraryJobStatus(byte[] b,LibraryJob job)throws IOException{
            if(b.length!=20||Wire.u16(b,1)!=job.id||(b[5]&255)!=job.operation||(b[6]&255)!=job.index||Wire.u32(b,7)!=job.crc||(b[3]&255)<1||(b[3]&255)>3||(b[11]&255)>1)throw new IOException("任务应答不匹配");
            state=b[3]&255;error=b[4]&255;persisted=b[11]!=0;
            if((persisted&&(state!=2||job.operation!=0))||(state==2&&error!=0))throw new IOException("任务持久状态矛盾");
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
        throw new IOException(cmd>=0x42&&cmd<=0x44?"任务启动应答超时，结果未知；勿重复发起擦写。重新验证后查询保留任务或曲目目录/CRC。":"响应超时，已发送4次相同请求；若模块仍已连接，请重新验证FPGA通信；若链路断开，请重连。未完成RAM上传需重新开始。");
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
    /** null is the explicit old-v1 fallback; other failures stay visible. */
    public LibraryCapabilities libraryCapabilities()throws IOException{
        try{return new LibraryCapabilities(request(0x40,new byte[0],20));}
        catch(DeviceError e){if(e.code==1)return null;throw e;}
    }
    public LibraryEntry libraryEntry(int index)throws IOException{
        if(index<0||index>=32)throw new IllegalArgumentException("invalid slot");
        LibraryEntry entry=new LibraryEntry(request(0x41,new byte[]{(byte)index},20));
        if(entry.index!=index)throw new IOException("曲目编号不匹配");return entry;
    }
    public LibraryJob startLibraryJob(int operation,int index,String shortName,long scoreCrc)throws IOException{
        if(operation<0||operation>2||index<0||index>=32)throw new IllegalArgumentException("invalid job");
        byte[] p=new byte[operation==0?8:1];p[0]=(byte)index;
        if(operation==0&&shortName!=null){if(shortName.length()>7)throw new IOException("琴端短名最多7个ASCII字符");for(int i=0;i<shortName.length();i++){char ch=shortName.charAt(i);if(ch<32||ch>126)throw new IOException("琴端短名仅支持ASCII");p[i+1]=(byte)ch;}}
        return new LibraryJob(Wire.u16(request(0x42+operation,p,3),1),operation,index,operation==0?scoreCrc:0);
    }
    public LibraryJobStatus libraryJob(LibraryJob job)throws IOException{return new LibraryJobStatus(request(0x45,job.token(),20),job);}
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
        switch(code){case 0x21:return "Flash未识别、未开放写入或未取得写使能";case 0x22:return "Flash忙等待超时；空闲后读取Flash诊断可刷新状态";case 0x23:return "Flash地址/页边界非法";case 0x24:return "Flash或曲库错误";case 0x25:return "Flash仍忙";case 0x28:return "任务结果未知或已被替代；请核对曲目目录/CRC";default:break;}
        switch(code){case 1:return "未知命令";case 2:return "协议版本错误";case 3:return "载荷长度错误";case 5:return "状态不允许";case 6:return "参数或音符非法";case 7:return "上传索引错误";case 8:return "容量不足";case 9:return "整曲CRC错误";case 10:return "整曲声部等约束不满足";case 11:return "序号冲突，需要重新HELLO";case 12:return "上传事务超时";case 13:return "内部错误";case 14:return "没有有效曲谱";default:return "未定义错误";}
    }
}
