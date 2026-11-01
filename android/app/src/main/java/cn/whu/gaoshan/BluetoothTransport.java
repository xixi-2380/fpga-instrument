package cn.whu.gaoshan;
import android.bluetooth.BluetoothSocket;
import cn.whu.gaoshan.core.ProtocolClient;
import java.io.*;
import java.util.concurrent.*;
import java.util.function.Consumer;
import cn.whu.gaoshan.core.Wire;

/** Socket reads never block UI. Queue overflow/EOF closes the session explicitly. */
final class BluetoothTransport implements ProtocolClient.Transport {
    private final BluetoothSocket socket;private final OutputStream output;
    private final ArrayBlockingQueue<Integer> bytes=new ArrayBlockingQueue<>(4096);
    private final ScheduledExecutorService watchdog=Executors.newSingleThreadScheduledExecutor();
    private volatile IOException failure;private volatile boolean closed;
    private final Consumer<String> trace;
    private final Consumer<IOException> failed;
    BluetoothTransport(BluetoothSocket socket,Consumer<IOException> failed,Consumer<String> trace)throws IOException{
        this.trace=trace;this.failed=failed;
        this.socket=socket;output=socket.getOutputStream();InputStream input=socket.getInputStream();
        Thread reader=new Thread(()->{try{byte[] b=new byte[512];while(!closed){int n=input.read(b);if(n<0)throw new EOFException("蓝牙连接已断开");trace.accept("RX "+n+" bytes: "+Wire.hex(java.util.Arrays.copyOf(b,Math.min(n,40)))+(n>40?" …":""));for(int i=0;i<n;i++)if(!bytes.offer(b[i]&255))throw new IOException("接收缓存溢出，请重连");}}
            catch(IOException e){fail(e);}},"SPP-reader");reader.setDaemon(true);reader.start();
    }
    private void fail(IOException e){synchronized(this){if(closed||failure!=null)return;failure=e;}try{socket.close();}catch(IOException ignored){}failed.accept(e);}
    private void check()throws IOException{if(failure!=null)throw failure;if(closed)throw new IOException("连接已关闭");}
    public void write(byte[] data)throws IOException{
        trace.accept("TX "+data.length+" bytes: "+Wire.hex(java.util.Arrays.copyOf(data,Math.min(data.length,40)))+(data.length>40?" …":""));
        check();ScheduledFuture<?> timeout;
        try{timeout=watchdog.schedule(()->fail(new IOException("蓝牙写入超时")),10,TimeUnit.SECONDS);}catch(RejectedExecutionException e){throw new IOException("连接已关闭",e);}
        try{output.write(data);output.flush();check();}catch(IOException e){fail(e);throw e;}finally{timeout.cancel(false);}
    }
    public int read(int timeoutMs)throws IOException{check();try{Integer b=bytes.poll(timeoutMs,TimeUnit.MILLISECONDS);check();return b==null?-1:b;}
        catch(InterruptedException e){Thread.currentThread().interrupt();throw new IOException("操作中断",e);}}
    public void drain()throws IOException{check();bytes.clear();}
    public void close()throws IOException{closed=true;watchdog.shutdownNow();socket.close();bytes.clear();}
}
