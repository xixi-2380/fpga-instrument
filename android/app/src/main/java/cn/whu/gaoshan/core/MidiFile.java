package cn.whu.gaoshan.core;

import java.nio.charset.StandardCharsets;
import java.util.*;

/** Strict bounded SMF 0/1, PPQN. Tempo map is global even when notes are filtered. */
public final class MidiFile {
    public static final int MAX_BYTES=2*1024*1024,MAX_EVENTS=100000;
    private static final class Event {
        long tick,ms;int track,channel,pitch,velocity,kind,tempo,index;
    }
    private static final class Reader {
        final byte[] b;int p,end;
        Reader(byte[] b,int p,int end){this.b=b;this.p=p;this.end=end;}
        int get(){if(p>=end)throw bad("文件意外结束");return b[p++]&255;}
        int be16(){return (get()<<8)|get();}
        long be32(){return ((long)get()<<24)|((long)get()<<16)|((long)get()<<8)|get();}
        long vlq(){long v=0;for(int k=0;k<4;k++){int n=get();v=(v<<7)|(n&127);if((n&128)==0)return v;}throw bad("变长整数超过4字节");}
        void skip(long n){if(n<0||n>end-p)throw bad("区块长度超限");p+=(int)n;}
        int data(){int n=get();if(n>=128)throw bad("非法MIDI数据字节");return n;}
    }
    public final int format,ppqn;public final List<String> tracks;
    private final List<Event> events=new ArrayList<>();private final Set<String> warnings=new LinkedHashSet<>();
    private static IllegalArgumentException bad(String text){return new IllegalArgumentException("MIDI："+text);}
    public MidiFile(byte[] bytes){
        if(bytes.length>MAX_BYTES)throw bad("文件超过2MiB");Reader r=new Reader(bytes,0,bytes.length);
        if(r.be32()!=0x4d546864L)throw bad("缺少MThd头");long h=r.be32();if(h<6||h>bytes.length-8)throw bad("头长度错误");
        format=r.be16();int count=r.be16(),division=r.be16();r.skip(h-6);
        if(format>1)throw bad("首版仅支持Format 0/1");if(count<1||count>256||(format==0&&count!=1))throw bad("轨道数量错误");
        if((division&0x8000)!=0||division==0)throw bad("仅支持PPQN，不支持SMPTE");ppqn=division;
        List<String> labels=new ArrayList<>();
        for(int track=0;track<count;track++){
            if(r.be32()!=0x4d54726bL)throw bad("缺少MTrk轨道");long length=r.be32();if(length>r.end-r.p)throw bad("轨道长度超限");
            Reader t=new Reader(bytes,r.p,r.p+(int)length);r.skip(length);long tick=0;int running=0;boolean ended=false;String name="轨道 "+(track+1);
            while(t.p<t.end){
                tick=Math.addExact(tick,t.vlq());if(events.size()>=MAX_EVENTS)throw bad("事件超过10万");
                int status=t.get();if(status<128){if(running==0)throw bad("running status无前置状态");t.p--;status=running;}
                if(status==0xff){running=0;int type=t.get();long size=t.vlq();if(size>t.end-t.p)throw bad("元事件长度超限");
                    if(type==0x2f){if(size!=0)throw bad("结束事件长度错误");ended=true;if(t.p!=t.end)throw bad("结束事件后还有轨道数据");break;}
                    if(type==0x51){if(size!=3)throw bad("速度事件长度错误");Event e=new Event();e.tick=tick;e.track=track;e.kind=2;e.tempo=(t.get()<<16)|(t.get()<<8)|t.get();if(e.tempo==0)throw bad("速度值为0");e.index=events.size();events.add(e);}
                    else if(type==3){int n=(int)size;name=new String(bytes,t.p,Math.min(n,120),StandardCharsets.UTF_8);t.skip(n);}
                    else t.skip(size);
                }else if(status==0xf0||status==0xf7){running=0;t.skip(t.vlq());warnings.add("文件含系统专用事件，首版将忽略；设备设置可能无法还原");}
                else if(status>=0x80&&status<=0xef){running=status;int kind=status>>>4,ch=status&15,a=t.data(),b=(kind==12||kind==13)?0:t.data();
                    if(kind==8||kind==9){Event e=new Event();e.tick=tick;e.track=track;e.channel=ch;e.pitch=a;e.velocity=b;e.kind=(kind==8||b==0)?0:1;e.index=events.size();events.add(e);}
                    else warnings.add("含踏板、音色、弯音或表情等控制事件，首版忽略这些控制，只按音高、力度与起止时间转换");
                }else throw bad("不支持的系统状态字节");
            }
            if(!ended)throw bad("轨道缺少结束事件");labels.add(name.isEmpty()?"轨道 "+(track+1):name);
        }
        if(r.p!=r.end)throw bad("尾部有未解释的数据");tracks=Collections.unmodifiableList(labels);
        events.sort(Comparator.<Event>comparingLong(e->e.tick).thenComparingInt(e->e.track).thenComparingInt(e->e.index));
        long lastTick=0,units=0,tempoTick=-1;int tempo=500000,tempoAtTick=0;
        for(Event e:events){
            units=Math.addExact(units,Math.multiplyExact(e.tick-lastTick,(long)tempo));lastTick=e.tick;
            long denominator=ppqn*1000L;e.ms=Math.addExact(units,denominator/2)/denominator;
            if(e.kind==2){if(tempoTick==e.tick&&tempoAtTick!=e.tempo)throw bad("同一时刻存在冲突速度事件");tempo=e.tempo;tempoTick=e.tick;tempoAtTick=tempo;}
        }
    }
    public Score convert(int track,int channel,int transpose){
        if(track<-1||track>=tracks.size()||channel<-1||channel>15||transpose<-48||transpose>48)throw bad("筛选或移调范围错误");
        Map<Integer,ArrayDeque<Event>> pending=new HashMap<>();ArrayList<Score.Note> notes=new ArrayList<>();Map<Score.Note,Integer> order=new IdentityHashMap<>();
        for(Event e:events){if(e.kind==2||(track>=0&&track!=e.track)||(channel>=0&&channel!=e.channel))continue;
            int key=e.channel*128+e.pitch;ArrayDeque<Event> q=pending.computeIfAbsent(key,k->new ArrayDeque<>());
            if(e.kind==1)q.addLast(e);
            else {if(q.isEmpty())throw bad("发现没有配对起音的结束事件（通道"+(e.channel+1)+"，音高"+e.pitch+"）");
                Event on=q.removeFirst();long duration=e.ms-on.ms;
                if(duration<1||duration>65535)throw bad("毫秒舍入后音符时长不在1～65535内，请修改原谱");
                Score.Note result=new Score.Note(on.ms,on.pitch+transpose,on.velocity,(int)duration);notes.add(result);order.put(result,on.index);}
        }
        for(ArrayDeque<Event> q:pending.values())if(!q.isEmpty())throw bad("文件结束时还有未关闭的音符");
        // Preserve start-time and original event order even if note-offs occur out of order.
        notes.sort(Comparator.<Score.Note>comparingLong(n->n.start).thenComparingInt(order::get));return new Score(notes,new ArrayList<>(warnings));
    }
}
