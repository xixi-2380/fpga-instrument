package cn.whu.gaoshan.core;
import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Protocol model tests only; no Android, SPI timing or physical persistence. */
public final class LibraryTests {
    private static int checks=0;
    private static void check(boolean value,String why){checks++;if(!value)throw new AssertionError(why);}
    private interface Action{void run()throws Exception;}
    private static void error(int code,Action action)throws Exception{try{action.run();throw new AssertionError("expected device error");}catch(ProtocolClient.DeviceError e){check(e.code==code,"error code");}}
    private static void complete(ProtocolClient c,ProtocolClient.LibraryJob key,boolean persisted)throws Exception{
        ProtocolClient.LibraryJobStatus state=c.libraryJob(key);check(state.state==1&&!state.persisted,"busy never claims persistence");
        state=c.libraryJob(key);check(state.state==2&&state.persisted==persisted,"final job state matches operation");
    }
    public static void main(String[] args)throws Exception{
        byte[] diag=new byte[20];diag[1]=1;diag[2]=3;diag[3]=32;Wire.put16(diag,4,4096);diag[6]=16;
        diag[7]=0x18;diag[8]=0x40;diag[9]=(byte)0xef;diag[10]=(byte)0xe0;diag[11]=0x3b;diag[12]=0x60;
        String diagnostic=ProtocolClient.flashDiagnostic(new ProtocolClient.LibraryCapabilities(diag));
        check(diagnostic.contains("ID=EF4018 SR1=E0 SR2=3B SR3=60"),"real raw status bytes are available for hardware diagnosis");
        check(diagnostic.contains("需核对固件")&&!diagnostic.contains("数据区保护已启用"),"register locks alone are not reported as array protection");
        diag[10]=4;diag[2]=7;check(ProtocolClient.flashDiagnostic(new ProtocolClient.LibraryCapabilities(diag)).contains("成功以读回校验为准"),"BP does not imply entire chip is unavailable");
        diag[10]=0;diag[12]=4;check(ProtocolClient.flashDiagnostic(new ProtocolClient.LibraryCapabilities(diag)).contains("芯片保护保持"),"individual lock mode does not imply every sector is locked");
        check(ProtocolClient.flashJobError(9).contains("0x09")&&ProtocolClient.flashJobError(9).contains("Flash读回"),"Flash CRC failure includes exact code and context");
        check(ProtocolClient.flashJobError(0x21).contains("0x21"),"write rejection code stays visible");
        SimulatedDevice device=new SimulatedDevice(true);ProtocolClient client=new ProtocolClient(device,()->System.nanoTime()/1000000L,10);
        ProtocolClient.Capabilities caps=client.hello();check(caps.maxNotes==4096&&caps.voices==16&&caps.features==5,"actual poly capacity, RAM feature semantics unchanged");
        check(caps.minNote==48&&caps.maxNote==83,"tested automatic range remains unchanged");
        ProtocolClient.LibraryCapabilities ext=client.libraryCapabilities();check(ext.writable&&ext.initialized&&ext.jedecId==0xef4018,"extension profile");
        List<Score.Note> notes=new ArrayList<>();for(int i=0;i<16;i++)notes.add(new Score.Note(0,60,112+i,10));
        Score score=new Score(notes,Collections.emptyList());score.validate(caps);check(score.polyphony==16,"same pitch overlap needs 16 voices");
        client.upload(score,new AtomicBoolean(),(n,total)->{});long crc=Wire.crc32(score.bytes());
        check(client.libraryCapabilities().activeCrc==crc,"current RAM fingerprint");
        device.dropCommand=0x42;device.dropCount=1;
        ProtocolClient.LibraryJob save=client.startLibraryJob(0,4,"CHORD16",crc);
        check(device.libraryStarts==1,"lost SAVE reply retries identical request without second task");
        error(5,()->client.command(0x20));check(client.sessionReady(),"BUSY retains session");
        check(client.libraryJob(save).state==1,"save remains asynchronous");
        client.hello();check(client.libraryJob(save).persisted,"re-HELLO can find prior save completion");
        ProtocolClient.LibraryEntry entry=client.libraryEntry(4);check(entry.exists&&entry.count==16&&entry.crc==crc&&entry.name.equals("CHORD16"),"directory matches committed data");
        error(0x28,()->client.libraryJob(new ProtocolClient.LibraryJob(save.id,0,4,crc^1)));check(client.sessionReady(),"wrong task fingerprint is explicitly unknown");
        device.powerCycle();client.hello();error(0x28,()->client.libraryJob(save));check(client.libraryEntry(4).crc==crc,"mock reboot keeps only committed library");
        ProtocolClient.LibraryJob load=client.startLibraryJob(1,4,"",0);complete(client,load,false);check(client.status().songValid,"loaded RAM validated");
        client.command(0x20);client.command(0x21);client.command(0x22);client.command(0x23);
        device.dropCommand=0x44;device.dropCount=1;int before=device.libraryStarts;
        ProtocolClient.LibraryJob delete=client.startLibraryJob(2,4,"",0);check(device.libraryStarts==before+1,"delete retry starts one task");complete(client,delete,false);
        device.powerCycle();client.hello();check(!client.libraryEntry(4).exists,"mock committed deletion survives reset");
        error(14,()->client.startLibraryJob(1,4,"",0));
        notes=new ArrayList<>();for(int i=0;i<4096;i++)notes.add(new Score.Note(i*2,60,100,1));Score full=new Score(notes,Collections.emptyList());
        client.upload(full,new AtomicBoolean(),(n,total)->{});check(client.status().total==4096,"full production capacity accepted");
        device.dropCommand=0x42;device.dropCount=4;int started=device.libraryStarts;
        long fullCrc=Wire.crc32(full.bytes());
        try{client.startLibraryJob(0,6,"FULL",fullCrc);throw new AssertionError("expected lost reply");}catch(IOException e){checks++;}
        check(device.libraryStarts==started+1,"all four lost startup replies still create exactly one job");
        client.hello();ProtocolClient.LibraryJob recovered=new ProtocolClient.LibraryJob(client.libraryCapabilities().latestJobId,0,6,fullCrc);
        complete(client,recovered,true);check(client.libraryEntry(6).crc==fullCrc,"startup acknowledgement loss can be reconciled by latest ID plus fingerprint");
        ProtocolClient old=new ProtocolClient(new SimulatedDevice());old.hello();check(old.libraryCapabilities()==null&&old.sessionReady(),"old v1 fallback consumes unknown-command sequence and remains usable");old.command(0x23);
        try{client.startLibraryJob(0,0,"中文",0);throw new AssertionError("ASCII required");}catch(IOException e){checks++;}
        byte[] inconsistent=new byte[20];Wire.put16(inconsistent,1,1);inconsistent[3]=1;inconsistent[11]=1;
        try{new ProtocolClient.LibraryJobStatus(inconsistent,new ProtocolClient.LibraryJob(1,0,0,0));throw new AssertionError("invalid persistence");}catch(IOException e){checks++;}
        if(args.length>0){
            String[] fixtures={"twinkle_polyphonic.mid","poly16_boundary_12ms.mid"};int[] sizes={78,48},poly={4,16};long[] durations={23750,12};
            for(int i=0;i<fixtures.length;i++){
                byte[] bytes=java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(args[0],fixtures[i]));
                Score parsed=new MidiFile(bytes).convert(-1,-1,0);parsed.validate(caps);
                check(parsed.notes.size()==sizes[i]&&parsed.polyphony==poly[i]&&parsed.duration==durations[i]&&parsed.warnings.isEmpty(),"actual MIDI parser accepts fixture "+fixtures[i]);
            }
        }
        System.out.println("PASS library: "+checks+" checks; protocol mock only, no Flash/phone verification");
    }
}
