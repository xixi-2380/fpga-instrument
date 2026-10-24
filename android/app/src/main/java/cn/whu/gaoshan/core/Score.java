package cn.whu.gaoshan.core;
import java.util.*;

public final class Score {
    public static final class Note {
        public final long start;public final int pitch,velocity,duration;
        public Note(long start,int pitch,int velocity,int duration){
            if(start<0||start>0xffffffffL||pitch<0||pitch>127||velocity<1||velocity>127||duration<1||duration>65535||start+duration>0xffffffffL)
                throw new IllegalArgumentException("音符超出协议范围（时长须为1～65535毫秒）");
            this.start=start;this.pitch=pitch;this.velocity=velocity;this.duration=duration;
        }
        public long end(){return start+duration;}
    }
    public final List<Note> notes;public final List<String> warnings;
    public final long duration;public final int polyphony,minPitch,maxPitch;
    public Score(List<Note> source,List<String> warnings){
        if(source.isEmpty())throw new IllegalArgumentException("所选声部没有音符");
        ArrayList<Note> copy=new ArrayList<>(source);copy.sort(Comparator.comparingLong(n->n.start));
        this.notes=Collections.unmodifiableList(copy);this.warnings=Collections.unmodifiableList(new ArrayList<>(warnings));
        long end=0;int lo=127,hi=0,max=0;PriorityQueue<Long> active=new PriorityQueue<>();
        for(Note n:copy){while(!active.isEmpty()&&active.peek()<=n.start)active.remove();active.add(n.end());max=Math.max(max,active.size());end=Math.max(end,n.end());lo=Math.min(lo,n.pitch);hi=Math.max(hi,n.pitch);}
        duration=end;polyphony=max;minPitch=lo;maxPitch=hi;
    }
    public byte[] bytes(){byte[] b=new byte[notes.size()*8];for(int i=0;i<notes.size();i++){Note n=notes.get(i);int p=i*8;Wire.put32(b,p,n.start);b[p+4]=(byte)n.pitch;b[p+5]=(byte)n.velocity;Wire.put16(b,p+6,n.duration);}return b;}
    public void validate(ProtocolClient.Capabilities c){
        if(notes.size()>c.maxNotes)throw new IllegalArgumentException("音符数量超过设备容量："+notes.size()+" / "+c.maxNotes);
        if(polyphony>c.voices)throw new IllegalArgumentException("所选声部最多同时发声"+polyphony+"个，设备允许"+c.voices+"个；请筛选轨道或通道");
        if(minPitch<c.minNote||maxPitch>c.maxNote)throw new IllegalArgumentException("音域超限，请移调或筛选声部；设备MIDI音域"+c.minNote+"～"+c.maxNote);
        if(duration>c.maxSongMs)throw new IllegalArgumentException("曲谱总时长超过设备上限");
    }
    public static Score golden(){return new Score(Arrays.asList(new Note(0,60,100,450),new Note(500,62,100,450),new Note(1000,64,100,900)),Collections.emptyList());}
}
