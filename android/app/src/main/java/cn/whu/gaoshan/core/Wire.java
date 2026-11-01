package cn.whu.gaoshan.core;

import java.io.ByteArrayOutputStream;
import java.util.Arrays;
import java.util.zip.CRC32;

public final class Wire {
    private Wire() {}
    public static int u16(byte[] b,int p){return (b[p]&255)|((b[p+1]&255)<<8);}
    public static long u32(byte[] b,int p){return (b[p]&255L)|((b[p+1]&255L)<<8)|((b[p+2]&255L)<<16)|((b[p+3]&255L)<<24);}
    public static void put16(byte[] b,int p,int v){b[p]=(byte)v;b[p+1]=(byte)(v>>>8);}
    public static void put32(byte[] b,int p,long v){for(int k=0;k<4;k++)b[p+k]=(byte)(v>>>(8*k));}
    public static int crc16(byte[] b,int start,int end){
        int c=0xffff;
        for(int i=start;i<end;i++){c^=(b[i]&255)<<8;for(int k=0;k<8;k++)c=((c<<1)^((c&0x8000)!=0?0x1021:0))&0xffff;}
        return c;
    }
    public static long crc32(byte[] bytes){CRC32 c=new CRC32();c.update(bytes);return c.getValue();}
    public static byte[] frame(int cmd,int seq,byte[] payload){
        if(cmd<0||cmd>255||seq<0||seq>65535||payload.length>256)throw new IllegalArgumentException("Frame field out of range");
        byte[] b=new byte[10+payload.length];b[0]=(byte)0xa5;b[1]=0x5a;b[2]=1;b[3]=(byte)cmd;
        put16(b,4,seq);put16(b,6,payload.length);System.arraycopy(payload,0,b,8,payload.length);
        put16(b,b.length-2,crc16(b,2,b.length-2));return b;
    }
    public static final class Frame {
        public final int version,cmd,seq;public final byte[] payload;
        Frame(byte[] b){version=b[2]&255;cmd=b[3]&255;seq=u16(b,4);payload=Arrays.copyOfRange(b,8,b.length-2);}
    }
    public static final class Decoder {
        private final ByteArrayOutputStream bytes=new ByteArrayOutputStream(266);
        private long first,last;
        public void reset(){bytes.reset();}
        public Frame accept(int value,long nowMs){
            if(bytes.size()>0&&(nowMs-last>200||nowMs-first>1000))reset();
            int n=bytes.size();value&=255;
            if(n==0){if(value==0xa5){bytes.write(value);first=nowMs;}last=nowMs;return null;}
            if(n==1){if(value==0x5a)bytes.write(value);else if(value==0xa5){reset();bytes.write(value);first=nowMs;}else reset();last=nowMs;return null;}
            bytes.write(value);last=nowMs;
            byte[] b=bytes.toByteArray();n=b.length;
            if(n>=8){int length=u16(b,6);if(length>256){reset();return null;}
                if(n==length+10){reset();if(crc16(b,2,n-2)!=u16(b,n-2))return null;return new Frame(b);}}
            return null;
        }
    }
    public static String hex(byte[] data){StringBuilder s=new StringBuilder();for(byte b:data)s.append(String.format("%02X ",b&255));return s.toString().trim();}
}
