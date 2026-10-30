package cn.whu.gaoshan.core;
/** Complete 36-key mapping, independent of phone preferences. */
public final class KeyMap {
 public final byte[] bytes;
 public KeyMap(byte[] value){if(value.length!=72)throw new IllegalArgumentException("Mapping must contain 36 keys");bytes=value.clone();for(int k=0;k<36;k++){int p=pitch(k),t=timbre(k);if(p<21||p>108||t>15&&t!=31)throw new IllegalArgumentException("Invalid key "+k);}}
 public static KeyMap defaults(){byte[] b=new byte[72];for(int k=0;k<36;k++){b[2*k]=(byte)(60+k);b[2*k+1]=31;}return new KeyMap(b);}
 public int pitch(int k){return bytes[2*k]&255;}public int timbre(int k){return bytes[2*k+1]&255;}
 public long crc(){return Wire.crc32(bytes);}
 public KeyMap with(int key,int pitch,int tone){byte[] b=bytes.clone();b[2*key]=(byte)pitch;b[2*key+1]=(byte)tone;return new KeyMap(b);}
}
