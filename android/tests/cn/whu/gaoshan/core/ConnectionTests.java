package cn.whu.gaoshan.core;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** State/ownership tests use fake transports, not a phone or RFCOMM stack. */
public final class ConnectionTests {
    private static int checks;
    private static void check(boolean ok,String why){checks++;if(!ok)throw new AssertionError(why);}
    private interface Job {void run()throws Exception;}
    private static void rejects(Job job)throws Exception{boolean rejected=false;try{job.run();}catch(IOException e){rejected=true;}check(rejected,"operation must fail");}
    private static final class Link implements ProtocolClient.Transport {
        final SimulatedDevice device=new SimulatedDevice();int writes,drains;volatile boolean closed,silent,blockingReads;
        final CountDownLatch readStarted=new CountDownLatch(1),readUnblock=new CountDownLatch(1);
        public void write(byte[] b)throws IOException{if(closed)throw new IOException("closed");writes++;if(!silent)device.write(b);}
        public int read(int timeout)throws IOException{if(blockingReads){readStarted.countDown();try{readUnblock.await();}catch(InterruptedException e){throw new IOException(e);}}if(closed)throw new IOException("closed");return silent?-1:device.read(timeout);}
        public void drain()throws IOException{drains++;device.drain();}
        public void close(){closed=true;readUnblock.countDown();}
    }
    private static final class Attempt implements ModuleConnection.Attempt {
        final Link link=new Link();boolean closed,fail,block;final CountDownLatch started=new CountDownLatch(1),unblock=new CountDownLatch(1);
        public ProtocolClient.Transport connect()throws IOException{started.countDown();if(block)try{unblock.await();}catch(InterruptedException e){throw new IOException(e);}if(closed||fail)throw new IOException("simulated RFCOMM failure");return link;}
        public void close(){closed=true;link.close();unblock.countDown();}
    }
    private static ModuleConnection session(){AtomicLong time=new AtomicLong();return new ModuleConnection((s,m,e)->{},t->new ProtocolClient(t,()->time.incrementAndGet(),1000));}
    public static void main(String[] args)throws Exception{
        try(ModuleConnection s=session()){
            rejects(s::verify);Attempt a=new Attempt();s.connect(secure->a,ModuleConnection.Mode.SECURE,1000);
            check(s.state()==ModuleConnection.State.MODULE_CONNECTED,"socket success independent of HELLO");
            check(a.link.writes==0&&a.link.drains==0,"connect sends ZERO protocol bytes");
            check(s.readyClient()==null,"device actions locked before verify");
            a.link.silent=true;rejects(s::verify);
            check(a.link.writes==4,"HELLO retries same request four times");
            check(!a.closed&&!a.link.closed&&s.state()==ModuleConnection.State.MODULE_CONNECTED,"HELLO timeout retains live module link");
            a.link.silent=false;check(s.verify().maxNotes==1024,"retry HELLO on same link succeeds");
            check(s.state()==ModuleConnection.State.READY&&s.readyClient()!=null,"ready only after verified capabilities");
            check(s.readyClient().upload(Score.golden(),new AtomicBoolean(),(n,total)->{})==1900,"existing upload works after staged connection");
            s.protocolFailed();check(s.state()==ModuleConnection.State.MODULE_CONNECTED&&!a.closed,"protocol failure permits HELLO retry");
            s.verify();s.disconnect();check(a.closed&&a.link.closed&&s.state()==ModuleConnection.State.DISCONNECTED,"disconnect releases owner");
        }
        try(ModuleConnection s=session()){
            Attempt first=new Attempt(),second=new Attempt();first.fail=true;List<Boolean> methods=new ArrayList<>();
            s.connect(secure->{methods.add(secure);return secure?first:second;},ModuleConnection.Mode.AUTO,1000);
            check(methods.equals(Arrays.asList(true,false))&&first.closed&&!second.closed,"bounded fallback closes secure socket before insecure");
            s.linkFailed(first,new IOException("late old reader"));check(s.state()==ModuleConnection.State.MODULE_CONNECTED,"obsolete failure cannot disconnect new owner");
            s.linkFailed(second,new IOException("EOF"));check(s.state()==ModuleConnection.State.DISCONNECTED&&second.closed,"EOF actively invalidates link");
        }
        try(ModuleConnection s=session()){
            AtomicInteger calls=new AtomicInteger();Attempt a=new Attempt();a.fail=true;
            rejects(()->s.connect(secure->{calls.incrementAndGet();return a;},ModuleConnection.Mode.INSECURE,1000));
            check(calls.get()==1&&s.state()==ModuleConnection.State.DISCONNECTED,"forced mode does not retry forever");
            calls.set(0);rejects(()->s.connect(secure->{calls.incrementAndGet();return new Attempt();},ModuleConnection.Mode.AUTO,1000,()->true));
            check(calls.get()==0,"cancelled queued work cannot start a late connection");
        }
        try(ModuleConnection s=session()){
            Attempt a=new Attempt();a.block=true;AtomicReference<Throwable> failure=new AtomicReference<>();
            Thread worker=new Thread(()->{try{s.connect(secure->a,ModuleConnection.Mode.SECURE,200);}catch(Throwable e){failure.set(e);}});worker.start();
            check(a.started.await(2,TimeUnit.SECONDS),"blocking connect started");s.disconnect();worker.join(2000);
            check(!worker.isAlive()&&failure.get() instanceof IOException,"cancel unblocks connect without UI wait");
            check(a.closed&&s.state()==ModuleConnection.State.DISCONNECTED,"cancelled result cannot revive connection");
            Attempt b=new Attempt();s.connect(secure->b,ModuleConnection.Mode.SECURE,1000);
            check(s.state()==ModuleConnection.State.MODULE_CONNECTED,"reconnect after cancel");
            Thread.sleep(250);check(!b.closed,"old deadline cannot close replacement");
        }
        try(ModuleConnection s=session()){
            Attempt a=new Attempt();a.block=true;rejects(()->s.connect(secure->a,ModuleConnection.Mode.SECURE,20));
            check(a.closed&&s.state()==ModuleConnection.State.DISCONNECTED,"watchdog closes and releases timed-out attempt");
        }
        try(ModuleConnection s=session()){
            AtomicInteger calls=new AtomicInteger();Attempt a=new Attempt();
            s.connect(secure->{check(secure,"auto starts secure");calls.incrementAndGet();return a;},ModuleConnection.Mode.AUTO,1000);
            check(calls.get()==1,"successful secure connection does not try another socket");
            a.link.blockingReads=true;AtomicReference<Throwable> failure=new AtomicReference<>();
            Thread verifier=new Thread(()->{try{s.verify();}catch(Throwable e){failure.set(e);}});verifier.start();
            check(a.link.readStarted.await(2,TimeUnit.SECONDS),"HELLO receive wait started");s.disconnect();verifier.join(2000);
            check(!verifier.isAlive()&&failure.get() instanceof IOException&&s.state()==ModuleConnection.State.DISCONNECTED,"cancel HELLO cannot revive stale module state");
        }
        try(ModuleConnection s=session()){
            CountDownLatch opened=new CountDownLatch(1),resume=new CountDownLatch(1);Attempt stale=new Attempt();AtomicReference<Throwable> failure=new AtomicReference<>();
            Thread old=new Thread(()->{try{s.connect(secure->{opened.countDown();try{resume.await();}catch(InterruptedException e){throw new IOException(e);}return stale;},ModuleConnection.Mode.SECURE,1000);}catch(Throwable e){failure.set(e);}});old.start();
            check(opened.await(2,TimeUnit.SECONDS),"old factory is pending");s.disconnect();Attempt current=new Attempt();s.connect(secure->current,ModuleConnection.Mode.INSECURE,1000);
            resume.countDown();old.join(2000);
            check(!old.isAlive()&&failure.get() instanceof IOException&&stale.closed&&!current.closed&&s.state()==ModuleConnection.State.MODULE_CONNECTED,"late socket creation closes only old owner");
        }
        System.out.println("PASS connection: "+checks+" checks; no phone/radio validation");
    }
}
