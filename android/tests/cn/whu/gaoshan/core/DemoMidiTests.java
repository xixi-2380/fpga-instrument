package cn.whu.gaoshan.core;

import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Acceptance checks for the listening demo, using the production MIDI parser. */
public final class DemoMidiTests {
    private static int checks;
    private static void check(boolean value,String why){checks++;if(!value)throw new AssertionError(why);}
    public static void main(String[] args)throws Exception{
        Path midiPath=Paths.get(args[0]),report=Paths.get(args[1]);
        MidiFile midi=new MidiFile(Files.readAllBytes(midiPath));
        Score score=midi.convert(-1,-1,0);
        ProtocolClient.Capabilities caps=new ProtocolClient.Capabilities(4096,16,48,83,5,9600,3600000);
        score.validate(caps);
        check(midi.format==0&&midi.ppqn==480&&midi.tracks.size()==1,"standard Format 0 / PPQN480");
        check(score.warnings.isEmpty(),"no ignored controls or missing notes");
        check(score.notes.size()==362&&score.duration==82000&&score.polyphony==16,"full arrangement dimensions");
        check(score.minPitch==48&&score.maxPitch==83,"entire supported pitch range");
        check(Arrays.equals(score.bytes(),Files.readAllBytes(report.resolve("expected_records.bin"))),"every converted note matches generated timing, pitch, velocity and duration");
        check(Wire.crc32(score.bytes())==0x911c00a0L,"record CRC32");
        long[][] sections={{0,24000},{26000,50000},{52000,76000},{78000,82000}};
        int[] counts={42,78,210,32},poly={1,4,8,16};
        for(int i=0;i<sections.length;i++){
            List<Score.Note> part=new ArrayList<>();
            for(Score.Note n:score.notes)if(n.start>=sections[i][0]&&n.start<sections[i][1]){
                check(n.end()<=sections[i][1],"note off within its section");part.add(n);
            }
            Score s=new Score(part,Collections.emptyList());
            check(s.notes.size()==counts[i]&&s.polyphony==poly[i],"section note count and peak voices "+i);
        }
        for(long[] rest:new long[][]{{24000,26000},{50000,52000},{76000,78000}})
            for(Score.Note n:score.notes)check(n.end()<=rest[0]||n.start>=rest[1],"rest has no held MIDI notes");
        // Filtering the melody channel must remain usable, and the full demo
        // must reject an old single-voice device rather than silently drop notes.
        check(midi.convert(-1,0,0).notes.size()==134,"channel filtering preserves note pairing");
        try{score.validate(new ProtocolClient.Capabilities(1024,1,48,83,1,9600,3600000));throw new AssertionError("old single voice should reject demo");}
        catch(IllegalArgumentException expected){checks++;}
        SimulatedDevice device=new SimulatedDevice(true);
        ProtocolClient client=new ProtocolClient(device,()->System.nanoTime()/1000000L,10);
        client.hello();client.upload(score,new AtomicBoolean(),(sent,total)->{});
        check(client.status().songValid&&client.status().total==362,"mock upload commits all notes");
        check(client.libraryCapabilities().activeCrc==Wire.crc32(score.bytes()),"mock upload record fingerprint");
        String result="{\n  \"passed\": true,\n  \"checks\": "+checks+",\n  \"notes\": 362,\n  \"duration_ms\": 82000,\n  \"polyphony\": 16,\n  \"crc32\": \"911C00A0\",\n  \"scope\": \"Production Android MIDI parser, exact records, section polyphony, rests and simulated upload. No physical phone, Bluetooth or FPGA playback verification.\"\n}\n";
        Files.write(report.resolve("parser_validation.json"),result.getBytes(StandardCharsets.UTF_8));
        System.out.println("PASS demo MIDI: "+checks+" checks; production parser and mock upload only");
    }
}
