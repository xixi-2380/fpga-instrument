package cn.whu.gaoshan.core;

import java.io.IOException;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;

/** Owns one cancellable module connection. Connecting NEVER sends protocol bytes. */
public final class ModuleConnection implements AutoCloseable {
    public enum State { DISCONNECTED, CONNECTING, MODULE_CONNECTED, VERIFYING, READY }
    public enum Mode { AUTO, SECURE, INSECURE }
    public interface Attempt {
        ProtocolClient.Transport connect() throws IOException;
        void close();
    }
    public interface Factory { Attempt open(boolean secure) throws IOException; }
    public interface ClientFactory { ProtocolClient create(ProtocolClient.Transport transport); }
    public interface Observer { void changed(State state, String message, Throwable failure); }
    private final Observer observer;
    private final ClientFactory clients;
    private final ScheduledExecutorService timer=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"SPP-timeout");t.setDaemon(true);return t;});
    private State state=State.DISCONNECTED;
    private long generation;
    private Attempt active;
    private ProtocolClient client;
    private boolean expired,closed;
    public ModuleConnection(Observer observer){this(observer,ProtocolClient::new);}
    public ModuleConnection(Observer observer,ClientFactory clients){this.observer=observer;this.clients=clients;}
    public synchronized State state(){return state;}
    public synchronized ProtocolClient readyClient(){return state==State.READY?client:null;}
    private void announce(State next,String text,Throwable failure){state=next;observer.changed(next,text,failure);}
    private void release(){if(client!=null){client.close();client=null;}if(active!=null){active.close();active=null;}}
    public synchronized void disconnect(){generation++;release();announce(State.DISCONNECTED,"已断开模块连接",null);}
    public synchronized void linkFailed(Attempt owner,IOException error){
        if(active!=owner)return;
        generation++;release();announce(State.DISCONNECTED,"蓝牙链路已断开",error);
    }
    /** Run on the single command worker; disconnect() is safe from the UI thread. */
    public void connect(Factory factory,Mode mode,long timeoutMs)throws IOException{
        connect(factory,mode,timeoutMs,()->false);
    }
    public void connect(Factory factory,Mode mode,long timeoutMs,BooleanSupplier cancelled)throws IOException{
        final long epoch;
        synchronized(this){if(closed||cancelled.getAsBoolean())throw new IOException("连接已取消");generation++;epoch=generation;release();announce(State.CONNECTING,"准备连接模块",null);}
        IOException last=null;
        boolean[] methods=mode==Mode.AUTO?new boolean[]{true,false}:new boolean[]{mode==Mode.SECURE};
        for(boolean secure:methods){
            Attempt attempt;
            synchronized(this){if(epoch!=generation)throw new IOException("连接已取消");announce(State.CONNECTING,"正在建立"+(secure?"安全":"兼容（insecure）")+" RFCOMM连接",null);}
            try{attempt=factory.open(secure);}catch(IOException e){last=e;continue;}
            synchronized(this){if(epoch!=generation){attempt.close();throw new IOException("连接已取消");}active=attempt;expired=false;}
            ScheduledFuture<?> deadline=timer.schedule(()->{
                synchronized(ModuleConnection.this){if(epoch==generation&&active==attempt&&state==State.CONNECTING){expired=true;attempt.close();}}
            },timeoutMs,TimeUnit.MILLISECONDS);
            long started=System.nanoTime();
            try{
                ProtocolClient.Transport transport=attempt.connect();
                synchronized(this){
                    if(epoch!=generation||expired){transport.close();throw new IOException(expired?"蓝牙建连超时":"连接已取消");}
                    client=clients.create(transport);
                    announce(State.MODULE_CONNECTED,"模块已连接（"+(secure?"安全":"兼容")+" RFCOMM，"+((System.nanoTime()-started)/1000000)+"ms）；尚未发送HELLO，请点击验证FPGA通信",null);
                }
                return;
            }catch(IOException e){
                synchronized(this){
                    boolean timedOut=expired;
                    attempt.close();if(active==attempt)active=null;
                    if(epoch!=generation)throw new IOException("连接已取消",e);
                    last=timedOut?new IOException("蓝牙建连超时",e):e;
                    observer.changed(state,(secure?"安全":"兼容")+" RFCOMM尝试失败",last);
                }
            }finally{deadline.cancel(false);}
        }
        synchronized(this){if(epoch==generation){release();announce(State.DISCONNECTED,"模块连接失败，可切换连接方式后重试",last);}}
        throw last==null?new IOException("模块连接失败"):last;
    }
    public ProtocolClient.Capabilities verify()throws IOException{
        final ProtocolClient c;final long epoch;
        synchronized(this){if(state!=State.MODULE_CONNECTED&&state!=State.READY)throw new IOException("请先连接蓝牙模块");epoch=generation;c=client;announce(State.VERIFYING,"模块已连接，正在发送HELLO验证FPGA",null);}
        try{
            ProtocolClient.Capabilities result=c.hello();
            synchronized(this){if(epoch!=generation)throw new IOException("验证已取消");announce(State.READY,"FPGA通信验证成功，电子琴就绪",null);}
            return result;
        }catch(IOException e){
            synchronized(this){if(epoch==generation)announce(State.MODULE_CONNECTED,"模块仍已连接；FPGA验证失败，可重新验证",e);}
            throw e;
        }
    }
    public synchronized void protocolFailed(){if(state==State.READY)announce(State.MODULE_CONNECTED,"协议会话失效，请重新验证FPGA",null);}
    @Override public synchronized void close(){if(closed)return;closed=true;disconnect();timer.shutdownNow();}
}
