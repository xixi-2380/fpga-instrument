import cn.whu.gaoshan.core.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class VerifyTwinkle {
    public static void main(String[] args)throws Exception {
        MidiFile midi=new MidiFile(Files.readAllBytes(Paths.get(args[0])));
        Score score=midi.convert(-1,-1,0);
        score.validate(new ProtocolClient.Capabilities(1024,1,48,83,1,9600,3600000));
        if(midi.format!=0||midi.ppqn!=480||midi.tracks.size()!=1||score.notes.size()!=42||score.duration!=23750||score.polyphony!=1||score.minPitch!=60||score.maxPitch!=69||!score.warnings.isEmpty())throw new AssertionError("Unexpected MIDI preview");
        if(!Arrays.equals(score.bytes(),Files.readAllBytes(Paths.get(args[1]))))throw new AssertionError("Every converted record must match the reference melody");
        // Also cover explicit single-track/channel selectors used by the UI.
        if(!Arrays.equals(score.bytes(),midi.convert(0,0,0).bytes()))throw new AssertionError("Track/channel filtering changes the score");
        SimulatedDevice peer=new SimulatedDevice();ProtocolClient client=new ProtocolClient(peer);client.hello();
        if(client.upload(score,new AtomicBoolean(),(n,total)->{})!=23750||peer.dataWrites!=3)throw new AssertionError("Software protocol upload differs");
        client.close();
        System.out.printf("PASS actual App MIDI parser: Format0 PPQN480, 42 notes, 1 voice, MIDI60..69, 23750ms, 336 record bytes, CRC32=%08X; software upload 3 DATA packets. No phone/radio test.%n",Wire.crc32(score.bytes()));
    }
}
