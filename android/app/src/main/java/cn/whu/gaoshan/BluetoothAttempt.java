package cn.whu.gaoshan;

import android.bluetooth.*;
import cn.whu.gaoshan.core.*;
import java.io.IOException;
import java.util.UUID;
import java.util.function.Consumer;

/** Every RFCOMM attempt owns its socket. No channel-1 reflection. */
final class BluetoothAttempt implements ModuleConnection.Attempt {
    private final BluetoothSocket socket;
    private final ModuleConnection owner;
    private final Consumer<String> trace;
    private BluetoothTransport transport;
    private boolean closed;
    BluetoothAttempt(BluetoothDevice device,boolean secure,ModuleConnection owner,Consumer<String> trace)throws IOException{
        this.owner=owner;this.trace=trace;
        UUID spp=UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
        try{socket=secure?device.createRfcommSocketToServiceRecord(spp):device.createInsecureRfcommSocketToServiceRecord(spp);}
        catch(SecurityException e){throw new IOException("没有蓝牙连接权限",e);}
    }
    public ProtocolClient.Transport connect()throws IOException{
        try{socket.connect();}catch(SecurityException e){throw new IOException("蓝牙连接权限被撤销",e);}
        synchronized(this){
            if(closed){socket.close();throw new IOException("连接已取消");}
            transport=new BluetoothTransport(socket,e->owner.linkFailed(this,e),trace);
            return transport;
        }
    }
    public synchronized void close(){closed=true;try{if(transport!=null)transport.close();else socket.close();}catch(IOException ignored){}}
}
