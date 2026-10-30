package cn.whu.gaoshan.core;
import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class CoreTests {
    static int checks=0;
    static void check(boolean ok,String why){checks++;if(!ok)throw new AssertionError(why);}
    interface Action {void run()throws Exception;}
    static void rejects(Action a,String why)throws Exception{boolean failed=false;try{a.run();}catch(IOException|IllegalArgumentException|ArithmeticException e){failed=true;}check(failed,why);}
    static byte[] hex(String s){String x=s.replace(" ","");byte[] b=new byte[x.length()/2];for(int i=0;i<b.length;i++)b[i]=(byte)Integer.parseInt(x.substring(i*2,i*2+2),16);return b;}
    static byte[] join(byte[]... arrays){ByteArrayOutputStream b=new ByteArrayOutputStream();for(byte[] a:arrays)b.write(a,0,a.length);return b.toByteArray();}
    static byte[] vlq(long n){int count=1;long x=n;while((x>>>=7)!=0)count++;byte[] b=new byte[count];for(int i=count-1;i>=0;i--){b[i]=(byte)((n&127)|(i<count-1?128:0));n>>>=7;}return b;}
    static byte[] event(int delta,int... bytes){byte[] b=new byte[bytes.length];for(int i=0;i<b.length;i++)b[i]=(byte)bytes[i];return join(vlq(delta),b);}
    static byte[] track(byte[]... events){byte[] raw=join(events);ByteArrayOutputStream b=new ByteArrayOutputStream();try{DataOutputStream d=new DataOutputStream(b);d.writeInt(0x4d54726b);d.writeInt(raw.length);d.write(raw);}catch(IOException e){throw new RuntimeException(e);}return b.toByteArray();}
    static byte[] smf(int format,int division,byte[]... tracks){ByteArrayOutputStream b=new ByteArrayOutputStream();try{DataOutputStream d=new DataOutputStream(b);d.writeInt(0x4d546864);d.writeInt(6);d.writeShort(format);d.writeShort(tracks.length);d.writeShort(division);for(byte[] t:tracks)d.write(t);}catch(IOException e){throw new RuntimeException(e);}return b.toByteArray();}
    static byte[] end(){return event(0,255,47,0);}
    static Score parse(byte[] b){return new MidiFile(b).convert(-1,-1,0);}
    static void wire()throws Exception{
        byte[] standard="123456789".getBytes("US-ASCII");check(Wire.crc16(standard,0,9)==0x29b1,"CRC16 standard");check(Wire.crc32(standard)==0xcbf43926L,"CRC32 standard");
        byte[] score=Score.golden().bytes();check(Wire.crc32(score)==0x7539bd9aL,"golden CRC32");
        check(Wire.hex(score).equals("00 00 00 00 3C 64 C2 01 F4 01 00 00 3E 64 C2 01 E8 03 00 00 40 64 84 03"),"golden score layout");
        String[] frames={"A5 5A 01 01 00 00 00 00 E1 E1","A5 5A 01 10 01 00 06 00 03 00 9A BD 39 75 7A 70","A5 5A 01 11 02 00 1A 00 00 00 00 00 00 00 3C 64 C2 01 F4 01 00 00 3E 64 C2 01 E8 03 00 00 40 64 84 03 57 62","A5 5A 01 12 03 00 00 00 B5 90","A5 5A 01 20 04 00 00 00 F5 89"};
        for(String s:frames){byte[] b=hex(s);Wire.Frame f=null;Wire.Decoder d=new Wire.Decoder();for(byte v:b)f=d.accept(v&255,0);check(f!=null,"decode golden");check(Arrays.equals(Wire.frame(f.cmd,f.seq,f.payload),b),"encode golden");}
        Random r=new Random(20261023);for(int size=0;size<=256;size++){
            byte[] p=new byte[size];r.nextBytes(p);if(size>2){p[0]=(byte)0xa5;p[1]=0x5a;}byte[] b=Wire.frame(0x91,345,p);
            for(int split=0;split<=b.length;split++){
                Wire.Decoder d=new Wire.Decoder();Wire.Frame f=null;long time=0;
                for(int i=0;i<split;i++)f=d.accept(b[i]&255,time++);
                for(int i=split;i<b.length;i++)f=d.accept(b[i]&255,time++);
                check(f!=null&&Arrays.equals(p,f.payload),"all split points and payload SOF");
            }
            b[b.length-1]^=1;Wire.Decoder d=new Wire.Decoder();Wire.Frame f=null;for(byte v:b)f=d.accept(v&255,0);check(f==null,"bad CRC discarded");
        }
        Wire.Decoder d=new Wire.Decoder();d.accept(0xa5,0);d.accept(0xa5,0);Wire.Frame got=null;byte[] hello=hex(frames[0]);for(int i=1;i<hello.length;i++)got=d.accept(hello[i]&255,0);check(got!=null,"overlapping SOF");
        d.accept(0xa5,0);d.accept(0x5a,0);got=null;for(byte b:hello)got=d.accept(b&255,201);check(got!=null,"interbyte timeout recovery");
        byte[] longFrame=Wire.frame(0x11,2,new byte[100]);got=null;for(int i=0;i<longFrame.length;i++)got=d.accept(longFrame[i]&255,300+i*15);check(got==null,"whole-frame timeout");
        byte[] tooLong={ (byte)0xa5,0x5a,1,0x11,1,0,1,1};for(byte b:tooLong)d.accept(b&255,3000);for(byte b:hello)got=d.accept(b&255,3000);check(got!=null,"oversize recovery");
    }
    static void midi()throws Exception{
        byte[] golden=smf(0,480,track(event(0,0x90,60,100),event(432,60,0),event(48,62,100),event(432,62,0),event(48,64,100),event(864,64,0),end()));
        Score s=parse(golden);check(Arrays.equals(s.bytes(),Score.golden().bytes()),"SMF running status and velocity zero golden conversion");
        MidiFile tempo=new MidiFile(smf(1,480,track(event(0,255,81,3,7,161,32),event(480,255,81,3,15,66,64),end()),track(event(0,0x90,60,100),event(960,0x80,60,0),end())));
        check(tempo.convert(1,-1,0).duration==1500,"Format1 global tempo map despite track filter");
        Score overlap=parse(smf(0,480,track(event(0,0x90,60,100),event(120,0x90,60,90),event(120,0x80,60,0),event(120,0x80,60,0),end())));
        check(overlap.polyphony==2&&overlap.notes.get(0).duration==250&&overlap.notes.get(1).start==125&&overlap.notes.get(1).duration==250,"same pitch FIFO overlap");
        Score stable=parse(smf(0,480,track(event(0,0x90,60,100),event(0,0x90,62,90),event(120,0x80,62,0),event(120,0x80,60,0),end())));
        check(stable.notes.get(0).pitch==60&&stable.notes.get(1).pitch==62,"stable same-start order independent of ends");
        MidiFile channel=new MidiFile(smf(0,480,track(event(0,0x90,60,100),event(0,0x91,64,100),event(480,0x80,60,0),event(0,0x81,64,0),end())));
        check(channel.convert(-1,1,12).notes.get(0).pitch==76,"channel filtering and transposition");
        check(parse(smf(0,480,track(event(0,0x90,60,100),event(480,0x80,60,0),event(0,0x90,62,100),event(480,0x80,62,0),end()))).polyphony==1,"half-open same-time off before on");
        check(parse(smf(0,1000,track(event(0,0x90,60,100),event(1,0x80,60,0),end()))).notes.get(0).duration==1,"half millisecond rounds up");
        check(parse(smf(0,480,track(event(0,0xb0,64,127),event(0,0x90,60,100),event(480,0x80,60,0),end()))).duration==500,"supported pedal closes at end of song");
        rejects(()->parse(smf(2,480,track(end()))),"format2 rejected");rejects(()->parse(smf(0,0xe728,track(end()))),"SMPTE rejected");
        rejects(()->parse(smf(0,480,track(event(0,0x80,60,0),end()))),"orphan off");
        rejects(()->parse(smf(0,480,track(event(0,0x90,60,100),end()))),"unclosed on");
        rejects(()->parse(smf(0,32767,track(event(0,0x90,60,100),event(1,0x80,60,0),end()))),"rounded zero duration");
        rejects(()->new MidiFile(smf(0,480,track(event(0,60,100),end()))),"running status without prior");
        rejects(()->new MidiFile(smf(0,480,track(event(0,0x90,60,100)))),"missing end track");
        rejects(()->new MidiFile(Arrays.copyOf(golden,golden.length-1)),"truncated file");
        rejects(()->channel.convert(-1,-1,100),"transpose bound");
        rejects(()->new MidiFile(smf(1,480,track(event(0,255,81,3,7,161,32),end()),track(event(0,255,81,3,15,66,64),end()))),"conflicting tempo events");
        ProtocolClient.Capabilities mono=new ProtocolClient.Capabilities(1024,1,48,83,1,9600,3600000);
        rejects(()->overlap.validate(mono),"device max overlap enforced");
        rejects(()->s.validate(new ProtocolClient.Capabilities(2,1,48,83,1,9600,3600000)),"capacity enforced");
        rejects(()->s.validate(new ProtocolClient.Capabilities(1024,1,65,83,1,9600,3600000)),"pitch enforced");
        rejects(()->s.validate(new ProtocolClient.Capabilities(1024,1,48,83,1,9600,1000)),"duration enforced");
    }
    static ProtocolClient client(SimulatedDevice peer){return new ProtocolClient(peer,()->System.nanoTime()/1000000L,20);}
    static void protocol()throws Exception{
        SimulatedDevice peer=new SimulatedDevice();ProtocolClient c=client(peer);
        rejects(()->c.command(0x20),"no HELLO no commands");ProtocolClient.Capabilities caps=c.hello();check(caps.voices==4&&caps.baud==9600,"parse HELLO");
        rejects(()->c.command(0x20),"no valid song");check(c.sessionReady(),"business error keeps session");
        peer.dropCommand=0x11;peer.dropCount=1;
        List<Integer> progress=new ArrayList<>();check(c.upload(Score.golden(),new AtomicBoolean(),(n,t)->progress.add(n))==1900,"end-to-end upload commit");
        check(peer.dataWrites==1,"lost DATA ack does not duplicate RAM writes");check(progress.equals(Arrays.asList(0,3)),"progress only confirmed records");
        ProtocolClient.Status s=c.status();check(s.songValid&&!s.uploading&&s.total==3&&s.received==3,"COMMIT valid status");
        peer.dropCommand=0x20;peer.dropCount=1;c.command(0x20);check(peer.playStarts==1,"lost PLAY ack does not restart");c.command(0x21);long pos=c.status().position;Thread.sleep(10);check(c.status().position==pos,"pause freezes music time");c.command(0x22);c.command(0x23);check(c.status().position==0,"STOP resets position");
        AtomicBoolean cancel=new AtomicBoolean();rejects(()->c.upload(Score.golden(),cancel,(n,t)->cancel.set(true)),"upload cancel");s=c.status();check(!s.songValid&&!s.uploading&&s.total==0,"ABORT confirmed and invalid half score");
        c.upload(Score.golden(),new AtomicBoolean(),(n,t)->{});c.command(0x20);c.hello();check(c.status().songValid&&c.status().state==1,"HELLO retains valid song and playback");c.command(0x23);
        peer.dropCommand=0x11;peer.dropCount=4;rejects(()->c.upload(Score.golden(),new AtomicBoolean(),(n,t)->{}),"retry exhaustion");check(!c.sessionReady(),"timeout invalidates session");c.hello();s=c.status();check(!s.uploading&&!s.songValid,"reHELLO cleans partial upload");c.close();
        // Full-capacity multi-packet transfer; BEGIN and COMMIT replies lost once.
        SimulatedDevice fullPeer=new SimulatedDevice();ProtocolClient full=client(fullPeer);full.hello();
        ArrayList<Score.Note> many=new ArrayList<>();for(int i=0;i<1024;i++)many.add(new Score.Note(i*10L,60,100,5));
        Score large=new Score(many,Collections.emptyList());fullPeer.dropCommand=0x10;fullPeer.dropCount=1;
        List<Integer> fullProgress=new ArrayList<>();check(full.upload(large,new AtomicBoolean(),(n,t)->fullProgress.add(n))==10235,"full-capacity upload");
        check(fullPeer.dataWrites==64&&fullProgress.size()==65&&fullProgress.get(64)==1024,"64 packets and confirmed progress");
        fullPeer.dropCommand=0x12;fullPeer.dropCount=1;check(full.upload(Score.golden(),new AtomicBoolean(),(n,t)->{})==1900,"lost COMMIT ack replay");
        full.close();
        // Direct reference transactions exercise same-sequence conflict and replay.
        peer=new SimulatedDevice();byte[] hello=Wire.frame(1,0,new byte[0]);peer.write(hello);peer.drain();byte[] bad=Wire.frame(0x23,2,new byte[0]);peer.write(bad);check(read(peer).payload[0]==11,"out of order conflict");
        byte[] stop=Wire.frame(0x23,1,new byte[0]);peer.write(stop);check(read(peer).payload[0]==0,"conflict does not advance expected");peer.write(Wire.frame(0x30,1,new byte[0]));check(read(peer).payload[0]==11,"same seq changed content conflict");peer.close();
    }
    static Wire.Frame read(SimulatedDevice p)throws Exception{Wire.Decoder d=new Wire.Decoder();for(int i=0;i<300;i++){int b=p.read(1);if(b<0)break;Wire.Frame f=d.accept(b,0);if(f!=null)return f;}throw new IOException("no reply");}
    public static void main(String[] args)throws Exception{wire();midi();protocol();System.out.println("PASS core: "+checks+" checks; wire/MIDI/session/upload/cancel/retry; software only");}
}
