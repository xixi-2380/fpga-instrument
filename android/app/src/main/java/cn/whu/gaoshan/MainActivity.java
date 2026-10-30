package cn.whu.gaoshan;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import cn.whu.gaoshan.core.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class MainActivity extends Activity {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final Handler handler=new Handler(Looper.getMainLooper());
    private volatile ProtocolClient client;private volatile int generation;
    private final ModuleConnection module=new ModuleConnection((state,text,error)->ui(()->{append(text);if(error!=null){append(error.getClass().getSimpleName()+": "+error.getMessage());android.util.Log.e("Gaoshan-SPP",text,error);}renderConnection();}));
    private ProtocolClient.Capabilities caps;private boolean busy=false,demo=false,dead=false;
    private final AtomicBoolean cancel=new AtomicBoolean();
    private MidiFile midi;private Score score;private String songName="未导入";
    private TextView status,capacity,summary,log,position,progressText,libraryInfo;private Spinner tracks,channels,librarySlots,timbreMode;private CheckBox excludeDrums;
    private ProtocolClient.LibraryCapabilities libraryCaps;
    private EditText transpose;private ProgressBar progress;private LinearLayout page;
    private Spinner connectionMode;private Button verifyButton;private String deviceLabel="";private boolean askedScanPermission;
    private final List<Button> lockedButtons=new ArrayList<>();private final List<Button> connectedButtons=new ArrayList<>();
    private final List<Button> performanceButtons=new ArrayList<>();
    private KeyMap editedMap;private TextView mapInfo,recordInfo;private Spinner mapBoard,mapKey,mapPitch,mapTone;
    private PerformanceRecording recordingDownload;private byte[] exportedMidi;
    private int pendingMapJob=-1;private long pendingMapCrc;
    private int ink=Color.rgb(228,236,239),muted=Color.rgb(164,183,191),accent=Color.rgb(104,219,193);
    private interface Job {void run()throws Exception;}
    private static final class FlashSaveFailure extends IOException {
        FlashSaveFailure(IOException cause){super("RAM下载与校验已完成；Flash保存未确认："+cause.getMessage(),cause);}
    }
    @Override public void onCreate(Bundle saved){super.onCreate(saved);getWindow().setStatusBarColor(Color.rgb(13,26,34));getWindow().setNavigationBarColor(Color.rgb(13,26,34));
        ScrollView scroll=new ScrollView(this);page=new LinearLayout(this);page.setOrientation(LinearLayout.VERTICAL);page.setPadding(dp(20),dp(28),dp(20),dp(32));page.setBackgroundColor(Color.rgb(13,26,34));scroll.addView(page);scroll.setOnApplyWindowInsetsListener((v,insets)->{page.setPadding(dp(20)+insets.getSystemWindowInsetLeft(),dp(20)+insets.getSystemWindowInsetTop(),dp(20)+insets.getSystemWindowInsetRight(),dp(24)+insets.getSystemWindowInsetBottom());return insets;});setContentView(scroll);
        label("高山流水",30,ink);label("曲谱传送 · 开发版 0.5 · MIDI多音色",14,accent);
        label("连接电子琴",20,ink);status=label("未连接设备",15,accent);capacity=label("先在系统蓝牙设置中配对模块。此 App 只列出已配对的经典蓝牙设备。",13,muted);
        label("第一步：仅连接蓝牙模块",15,ink);
        connectionMode=new Spinner(this);setItems(connectionMode,new String[]{"自动兼容：安全失败后尝试 insecure","仅安全 RFCOMM","仅兼容 insecure RFCOMM"});page.addView(connectionMode);
        row(button("连接蓝牙模块",this::chooseDevice,false),button("离线演示",this::startDemo,false));
        Button disconnect=button("断开连接",this::disconnect,false);lockedButtons.remove(disconnect);page.addView(disconnect);
        label("第二步：独立验证 FPGA 通信",15,ink);
        verifyButton=button("验证 FPGA 通信（HELLO）",this::verifyFpga,false);page.addView(verifyButton);
        label("模块连接成功后再点击验证；第一步不发送任何协议数据。",13,muted);
        label("导入与选择",20,ink);row(button("导入 MIDI",this::pickMidi,false),button("三音符示例",this::golden,false));
        tracks=new Spinner(this);channels=new Spinner(this);setItems(tracks,new String[]{"全部轨道"});setItems(channels,new String[]{"全部通道"});
        label("轨道",13,muted);page.addView(tracks);label("MIDI 通道",13,muted);page.addView(channels);
        timbreMode=new Spinner(this);String[] modes=new String[18];modes[0]="按原谱音色（默认）";for(int i=0;i<16;i++)modes[i+1]="统一旋律："+Timbres.NAMES[i];modes[17]="旧协议：琴端统一音色（须排除鼓轨）";setItems(timbreMode,modes);page.addView(timbreMode);excludeDrums=new CheckBox(this);excludeDrums.setText("排除第10通道鼓轨");excludeDrums.setTextColor(ink);page.addView(excludeDrums);
        transpose=new EditText(this);transpose.setSingleLine(true);transpose.setText("0");transpose.setTextColor(ink);transpose.setHintTextColor(muted);transpose.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_SIGNED);transpose.setHint("移调半音：-48 ～ +48");page.addView(transpose);
        page.addView(button("应用筛选与移调",this::convert,false));summary=label("尚无曲谱。导入后检查轨道、音域和声部数。",14,ink);
        label("传送到琴",20,ink);progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(1000);page.addView(progress);progressText=label("尚未上传",13,muted);
        row(button("下载到琴",this::confirmUpload,true),button("取消传送/等待",()->{cancel.set(true);append("已请求取消RAM上传或停止等待；已启动的Flash任务可能继续，请查询任务结果。");},false));
        // Cancellation must remain available during upload.
        lockedButtons.remove(lockedButtons.get(lockedButtons.size()-1));
        label("播放控制",20,ink);
        row(button("播放",()->playCommand(0x20),true),button("暂停",()->playCommand(0x21),true));
        row(button("继续",()->playCommand(0x22),true),button("停止",()->playCommand(0x23),true));
        page.addView(button("刷新设备状态",this::refreshStatus,true));position=label("进度由设备状态返回，不在手机端猜测。",13,muted);
        label("琴端曲库",20,ink);librarySlots=new Spinner(this);String[] slots=new String[32];for(int i=0;i<32;i++)slots[i]=String.format(Locale.ROOT,"S%03d",i+1);setItems(librarySlots,slots);page.addView(librarySlots);
        libraryInfo=label("下载校验后，如支持可写曲库，将自动保存到选定编号；旧RAM固件仍只下载到RAM。",13,muted);
        page.addView(button("读取Flash诊断",this::readFlashDiagnostics,true));
        row(button("刷新曲库目录",this::refreshLibrary,true),button("查询未完成任务",this::queryPendingJob,true));
        row(button("保存当前RAM",()->libraryAction(0),true),button("加载选中曲谱",()->libraryAction(1),true));
        page.addView(button("删除选中曲谱",()->{int index=librarySlots.getSelectedItemPosition();new AlertDialog.Builder(this).setMessage(String.format(Locale.ROOT,"删除琴端 S%03d？",index+1)).setNegativeButton("取消",null).setPositiveButton("确认删除",(d,w)->runLibraryAction(2,index)).show();},true));
        buildPerformanceUi();
        label("连接记录",20,ink);log=label("等待操作。离线演示不使用蓝牙，也不驱动扬声器。",12,muted);
        Button copy=button("复制诊断记录",()->{android.content.ClipboardManager clipboard=(android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE);clipboard.setPrimaryClip(ClipData.newPlainText("蓝牙诊断","高山流水 0.5-performance\n设备："+deviceLabel+"\n状态："+module.state()+"\n"+log.getText()));Toast.makeText(this,"诊断记录已复制",Toast.LENGTH_SHORT).show();},false);lockedButtons.remove(copy);page.addView(copy);render();
    }
    private int dp(int n){return (int)(getResources().getDisplayMetrics().density*n+.5f);}
    private TextView label(String text,int size,int color){TextView v=new TextView(this);v.setText(text);v.setTextSize(size);v.setTextColor(color);v.setPadding(0,dp(10),0,dp(6));page.addView(v);return v;}
    private Button button(String text,Runnable action,boolean needsConnection){Button b=new Button(this);b.setText(text);b.setAllCaps(false);b.setMinHeight(dp(52));b.setOnClickListener(v->action.run());lockedButtons.add(b);if(needsConnection)connectedButtons.add(b);return b;}
    private void row(Button a,Button b){LinearLayout l=new LinearLayout(this);l.setOrientation(LinearLayout.HORIZONTAL);l.addView(a,new LinearLayout.LayoutParams(0,-2,1));l.addView(b,new LinearLayout.LayoutParams(0,-2,1));page.addView(l);}
    private void setItems(Spinner s,String[] items){ArrayAdapter<String> adapter=new ArrayAdapter<String>(this,android.R.layout.simple_spinner_item,items){@Override public View getView(int position,View convertView,ViewGroup parent){TextView text=(TextView)super.getView(position,convertView,parent);text.setTextColor(ink);text.setPadding(dp(8),dp(12),dp(8),dp(12));return text;}};adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);s.setAdapter(adapter);}
    private void render(){for(Button b:lockedButtons)b.setEnabled(!busy&&(!connectedButtons.contains(b)||client!=null&&caps!=null));tracks.setEnabled(!busy&&midi!=null);channels.setEnabled(!busy&&midi!=null);transpose.setEnabled(!busy&&midi!=null);timbreMode.setEnabled(!busy);excludeDrums.setEnabled(!busy);if(librarySlots!=null)librarySlots.setEnabled(!busy);
        for(Button b:performanceButtons)b.setEnabled(!busy&&client!=null&&caps!=null&&client.performanceSupported);
        if(mapBoard!=null){mapBoard.setEnabled(!busy&&editedMap!=null);mapKey.setEnabled(!busy&&editedMap!=null);mapPitch.setEnabled(!busy&&editedMap!=null);mapTone.setEnabled(!busy&&editedMap!=null);}
        ModuleConnection.State state=module.state();verifyButton.setEnabled(!busy&&!demo&&(state==ModuleConnection.State.MODULE_CONNECTED||state==ModuleConnection.State.READY));connectionMode.setEnabled(!busy);}
    private void renderConnection(){
        if(status==null||demo)return;
        ModuleConnection.State state=module.state();
        if(state!=ModuleConnection.State.READY){caps=null;libraryCaps=null;client=null;}
        switch(state){
            case DISCONNECTED:status.setText("未连接模块");capacity.setText("请连接已配对设备；失败详情见连接记录。");position.setText("设备状态未知；断开连接不代表琴端停止播放。");break;
            case CONNECTING:status.setText("正在连接模块 · "+deviceLabel);break;
            case MODULE_CONNECTED:status.setText("模块已连接 · FPGA尚未验证");capacity.setText("蓝牙连接已建立。点击第二步验证；也可以仅测试断开和重连。");break;
            case VERIFYING:status.setText("模块已连接 · 正在验证FPGA");break;
            case READY:status.setText("模块已连接 · FPGA通信正常");break;
        }
        render();
    }
    private void append(String s){if(dead)return;String old=log.getText().toString();if(old.length()>6000)old=old.substring(old.length()-4000);log.setText(old+"\n"+new java.text.SimpleDateFormat("HH:mm:ss.SSS",Locale.ROOT).format(new Date())+" "+s);}
    private void ui(Runnable r){runOnUiThread(()->{if(!dead)r.run();});}
    private void task(String name,Job job){if(busy)return;busy=true;render();int epoch=generation;append(name+"…");worker.execute(()->{
        try{if(epoch!=generation)return;job.run();}
        catch(Exception e){ui(()->{if(epoch==generation){append(name+"失败："+e.getMessage());if(name.equals("上传曲谱"))progressText.setText(e instanceof FlashSaveFailure?e.getMessage():"RAM下载未完成："+e.getMessage());if(client!=null&&!client.sessionReady()){caps=null;if(!demo)module.protocolFailed();}new AlertDialog.Builder(this).setTitle(name+"未完成").setMessage(e.getMessage()).setPositiveButton("知道了",null).show();}});}
        finally{ui(()->{if(epoch==generation){busy=false;render();}});}
    });}
    private boolean permission(){if(Build.VERSION.SDK_INT>=31&&(checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED||(!askedScanPermission&&checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)!=PackageManager.PERMISSION_GRANTED))){askedScanPermission=true;requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_SCAN},7);return false;}return true;}
    @Override public void onRequestPermissionsResult(int r,String[] p,int[] g){super.onRequestPermissionsResult(r,p,g);if(r==7){if(checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED)chooseDevice();else append("未获附近设备连接权限；请在系统设置授权。");}}
    private void chooseDevice(){if(!permission())return;try{BluetoothManager manager=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);BluetoothAdapter adapter=manager==null?null:manager.getAdapter();
        if(adapter==null){message("此设备没有可用的经典蓝牙适配器");return;}if(!adapter.isEnabled()){startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),12);return;}
        ArrayList<BluetoothDevice> devices=new ArrayList<>(adapter.getBondedDevices());devices.sort(Comparator.comparing(d->String.valueOf(d.getName())));
        if(devices.isEmpty()){new AlertDialog.Builder(this).setMessage("没有已配对设备。请先到系统蓝牙设置中配对模块。").setPositiveButton("蓝牙设置",(d,w)->startActivity(new Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS))).setNegativeButton("取消",null).show();return;}
        String[] names=new String[devices.size()];for(int i=0;i<names.length;i++)names[i]=devices.get(i).getName()+"\n"+devices.get(i).getAddress();
        new AlertDialog.Builder(this).setTitle("选择已配对的 SPP 模块").setItems(names,(d,index)->connect(devices.get(index))).setNegativeButton("取消",null).show();
        }catch(SecurityException e){message("蓝牙权限不可用，请在应用设置中允许附近设备权限。" );append("列出已配对设备失败："+e.getMessage());}
    }
    private void connect(BluetoothDevice device){disconnect();demo=false;try{deviceLabel=(device.getName()==null?"未命名模块":device.getName())+" · "+device.getAddress();}catch(SecurityException e){message("蓝牙权限已撤销，请重新授权。");return;}int epoch=generation;
        int choice=connectionMode.getSelectedItemPosition();ModuleConnection.Mode mode=choice==1?ModuleConnection.Mode.SECURE:choice==2?ModuleConnection.Mode.INSECURE:ModuleConnection.Mode.AUTO;
        task("连接蓝牙模块",()->{
            BluetoothAdapter adapter=((BluetoothManager)getSystemService(BLUETOOTH_SERVICE)).getAdapter();
            try{if(Build.VERSION.SDK_INT<31||checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED){adapter.cancelDiscovery();}else ui(()->append("未授权扫描控制，跳过停止系统扫描；仍尝试连接已配对设备。"));}
            catch(SecurityException e){ui(()->append("停止扫描未获授权，继续建连："+e.getMessage()));}
            module.connect(secure->new BluetoothAttempt(device,secure,module,text->ui(()->append(text))),mode,12000,()->epoch!=generation);
        });
    }
    private void verifyFpga(){int epoch=generation;task("验证FPGA通信",()->{ProtocolClient.Capabilities cap=module.verify();ProtocolClient verified=module.readyClient();if(verified==null)throw new IOException("验证后连接已断开");ProtocolClient.Status actual;ProtocolClient.LibraryCapabilities ext;try{actual=verified.status();ext=verified.libraryCapabilities();verified.audioCapabilities();verified.performanceCapabilities();}catch(IOException e){module.protocolFailed();throw e;}ui(()->{if(epoch==generation&&module.state()==ModuleConnection.State.READY){client=verified;caps=cap;libraryCaps=ext;showCapacity(cap);showStatus(actual);showLibraryCapabilities(ext);append("HELLO及状态查询已确认；设备报告 UART "+cap.baud+" bit/s。");}});});}
    private void showCapacity(ProtocolClient.Capabilities c){capacity.setText((demo?"模拟能力（非实板）：":"设备报告：")+(client!=null&&client.multitimbral?"16种旋律音色＋10种鼓音\n":"仅支持旧模式：8字节曲谱\n")+c.maxNotes+" 条音符 / "+c.voices+" 声部 / MIDI "+c.minNote+"～"+c.maxNote+"\n"+((c.features&2)==0?"曲谱保存在RAM，断电丢失。":"设备声明掉电保留；以实际固件为准。"));}
    private void startDemo(){disconnect();demo=true;deviceLabel="DEMO";int epoch=generation;task("启动离线演示",()->{ProtocolClient c=new ProtocolClient(new SimulatedDevice(true));client=c;ProtocolClient.Capabilities cap=c.hello();c.audioCapabilities();c.performanceCapabilities();ProtocolClient.LibraryCapabilities ext=c.libraryCapabilities();ui(()->{if(epoch==generation){caps=cap;libraryCaps=ext;status.setText("离线演示 · 未连接FPGA");showCapacity(cap);showLibraryCapabilities(ext);append("现在只与手机内模拟设备通信，不发声，不证明硬件通过；演示曲库关闭App后不保留。");}});});}
    private void disconnect(){generation++;cancel.set(true);ProtocolClient c=client;client=null;caps=null;libraryCaps=null;if(c!=null)c.close();module.disconnect();busy=false;if(status!=null){status.setText("未连接模块");capacity.setText("可以连接已配对的SPP模块，或先用离线演示。");render();}}
    private void pickMidi(){Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.setType("*/*");i.addCategory(Intent.CATEGORY_OPENABLE);startActivityForResult(i,11);}
    @Override protected void onActivityResult(int request,int result,Intent intent){super.onActivityResult(request,result,intent);if(request==13){if(result!=RESULT_OK){append("MIDI export cancelled; capture retained");return;}if(intent==null||intent.getData()==null||exportedMidi==null)return;final Uri output=intent.getData();final byte[] bytes=exportedMidi;task("Export MIDI",()->{try(OutputStream stream=getContentResolver().openOutputStream(output,"wt")){if(stream==null)throw new IOException("Cannot open destination");stream.write(bytes);}ui(()->recordInfo.setText("MIDI saved; device recording retained"));});return;}if(request==12){if(result==RESULT_OK)chooseDevice();else append("蓝牙未开启，未发起连接。");return;}if(request!=11||result!=RESULT_OK||intent==null||intent.getData()==null)return;Uri uri=intent.getData();
        task("读取MIDI",()->{String name="导入曲谱.mid";try(Cursor cursor=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)){if(cursor!=null&&cursor.moveToFirst())name=cursor.getString(0);}
            if(name==null||!(name.toLowerCase(Locale.ROOT).endsWith(".mid")||name.toLowerCase(Locale.ROOT).endsWith(".midi")))throw new IOException("请选择.mid或.midi文件");
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();try(InputStream in=getContentResolver().openInputStream(uri)){if(in==null)throw new IOException("无法打开所选文件");byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){if(bytes.size()+n>MidiFile.MAX_BYTES)throw new IOException("MIDI文件超过2MiB限制");bytes.write(b,0,n);}}
            MidiFile parsed=new MidiFile(bytes.toByteArray());String label=name;ui(()->{midi=parsed;score=null;songName=label;String[] ts=new String[parsed.tracks.size()+1];ts[0]="全部轨道";for(int k=1;k<ts.length;k++)ts[k]=k+" · "+parsed.tracks.get(k-1);setItems(tracks,ts);String[] cs=new String[17];cs[0]="全部通道";for(int k=1;k<17;k++)cs[k]="通道 "+k;setItems(channels,cs);transpose.setText("0");summary.setText("已导入："+songName+"\nFormat "+parsed.format+" / PPQN "+parsed.ppqn+"\n请选择轨道／通道，再点击“应用筛选与移调”。");});
        });
    }
    private void golden(){midi=null;score=Score.golden();songName="三音符示例（C4 D4 E4）";showScore();render();}
    private void convert(){if(midi==null){message("先导入MIDI；三音符示例可直接下载。");return;}int shift;try{shift=Integer.parseInt(transpose.getText().toString().trim());}catch(Exception e){message("移调请输入-48到48的整数");return;}
        MidiFile file=midi;int tr=tracks.getSelectedItemPosition()-1,ch=channels.getSelectedItemPosition()-1;int semitones=shift;int tone=timbreMode.getSelectedItemPosition()==17?-2:timbreMode.getSelectedItemPosition()-1;boolean omitDrums=excludeDrums.isChecked();if(tone==-2&&!omitDrums){message("旧协议不支持鼓组，请勾选排除鼓轨。");return;}
        task("转换曲谱",()->{Score converted=file.convert(tr,ch,semitones,tone,omitDrums);ui(()->{score=converted;showScore();});});
    }
    private void showScore(){Score s=score;summary.setText(songName+"\n"+s.notes.size()+" 条音符 · "+String.format(Locale.ROOT,"%.3f",s.duration/1000.0)+" 秒 · 最大同时 "+s.polyphony+" 音\nMIDI音域 "+s.minPitch+"～"+s.maxPitch+" · 数据 "+s.bytes().length+" 字节\nCRC32 "+String.format(Locale.ROOT,"%08X",Wire.crc32(s.bytes()))+(s.warnings.isEmpty()?"":"\n⚠ 简化演奏："+String.join("；",s.warnings)));}
    private void confirmUpload(){Score s=score;ProtocolClient.Capabilities cap=caps;if(s==null||cap==null){message("请先生成曲谱预览，并连接设备或进入离线演示");return;}try{s.validate(cap);}catch(Exception e){message(e.getMessage());return;}
        String text=(demo?"【离线模拟，无真实设备】\n":"")+songName+"\n"+s.notes.size()+" 条音符，"+s.duration+" ms。\n开始上传后会替换琴上RAM原曲。"+(libraryCaps!=null&&libraryCaps.writable?String.format(Locale.ROOT,"校验后自动保存到 S%03d，并替换该编号已有曲谱。多音色保存会升级曲库目录，旧固件不能读取升级后的曲库。",librarySlots.getSelectedItemPosition()+1):"当前仅保存RAM，断电丢失。")+(s.warnings.isEmpty()?"":"\n\n将按简化方式演奏：\n"+String.join("\n",s.warnings));
        new AlertDialog.Builder(this).setTitle("确认下载曲谱").setMessage(text).setNegativeButton("取消",null).setPositiveButton("确认下载",(dialog,which)->upload(s)).show();
    }
    private void upload(Score s){
        cancel.set(false);int epoch=generation,index=librarySlots.getSelectedItemPosition();
        task("上传曲谱",()->{
            ProtocolClient c=client;if(c==null)throw new IOException("连接已断开");
            c.upload(s,cancel,(n,total)->ui(()->{if(epoch==generation){progress.setProgress((int)(n*1000L/total));progressText.setText("已确认 "+n+" / "+total+" 条；等待RAM校验");}}));
            ui(()->{if(epoch==generation){progressText.setText("RAM已校验；尚未持久保存");append("RAM下载与校验已完成。进入Flash保存阶段。");}});
            try{
                ProtocolClient.LibraryCapabilities ext=c.libraryCapabilities();
                ui(()->{if(epoch==generation){libraryCaps=ext;showLibraryCapabilities(ext);append(ProtocolClient.flashDiagnostic(ext));}});
                if(ext!=null&&ext.initialized&&ext.writable){
                    ProtocolClient.LibraryJob job=startTrackedJob(c,0,index,Wire.crc32(s.bytes()));waitLibraryJob(c,job,epoch);
                }else ui(()->{if(epoch==generation)progressText.setText("RAM下载完成；Flash尚不可写，断电不保留。请查看Flash诊断。");});
            }catch(IOException e){throw new FlashSaveFailure(e);}
        });
    }
    private void readFlashDiagnostics(){
        int epoch=generation;task("读取Flash诊断",()->{
            ProtocolClient.LibraryCapabilities ext=client.libraryCapabilities();
            ui(()->{if(epoch==generation){libraryCaps=ext;showLibraryCapabilities(ext);String text=ProtocolClient.flashDiagnostic(ext);append(text);new AlertDialog.Builder(this).setTitle("Flash诊断").setMessage(text+"\n可点“复制诊断记录”发送此结果。").setPositiveButton("知道了",null).show();}});
        });
    }
    private void showLibraryCapabilities(ProtocolClient.LibraryCapabilities ext){libraryInfo.setText(ext==null?"旧版RAM固件：不支持Flash曲库。":String.format(Locale.ROOT,"Flash ID %06X · %s · 32首\nRAM下载与Flash保存为两个独立阶段。",ext.jedecId,ext.writable?"允许写入，保存后读回确认":ext.supported?"忙或未开放写入":"未识别到有效Flash"));}
    private void refreshLibrary(){int epoch=generation;task("读取曲库",()->{ProtocolClient c=client;ProtocolClient.LibraryCapabilities ext=c.libraryCapabilities();if(ext==null)throw new IOException("当前固件不支持曲库");String[] names=new String[32];for(int i=0;i<32;i++){ProtocolClient.LibraryEntry e=c.libraryEntry(i);names[i]=String.format(Locale.ROOT,"S%03d · %s",i+1,e.exists?e.name+" / "+e.count+"音符":"空");}ui(()->{if(epoch==generation){int selection=librarySlots.getSelectedItemPosition();setItems(librarySlots,names);librarySlots.setSelection(selection);libraryCaps=ext;showLibraryCapabilities(ext);}});});}
    private void libraryAction(int op){int index=librarySlots.getSelectedItemPosition();if(op==0)new AlertDialog.Builder(this).setMessage(String.format(Locale.ROOT,"将当前RAM保存到 S%03d，替换该编号已有曲谱？",index+1)).setNegativeButton("取消",null).setPositiveButton("确认保存",(d,w)->runLibraryAction(op,index)).show();else runLibraryAction(op,index);}
    private void runLibraryAction(int op,int index){cancel.set(false);int epoch=generation;task("曲库操作",()->{ProtocolClient c=client;ProtocolClient.LibraryCapabilities ext=c.libraryCapabilities();if(ext==null)throw new IOException("当前固件不支持曲库");ProtocolClient.LibraryJob job=startTrackedJob(c,op,index,op==0?ext.activeCrc:0);waitLibraryJob(c,job,epoch);});}
    private ProtocolClient.LibraryJob startTrackedJob(ProtocolClient c,int op,int index,long crc)throws IOException{
        if(!getSharedPreferences("libraryJob",MODE_PRIVATE).edit().putBoolean("pending",true).putString("device",deviceLabel).putInt("id",-1).putInt("op",op).putInt("index",index).putLong("crc",crc).commit())throw new IOException("无法保留任务意图，未发起Flash任务");
        try{ProtocolClient.LibraryJob job=c.startLibraryJob(op,index,"",crc);rememberJob(job);ui(()->append(String.format(Locale.ROOT,"Flash任务 JOB=%04X OP=%d SLOT=S%03d CRC=%08X",job.id,job.operation,job.index+1,job.crc)));return job;}
        catch(ProtocolClient.DeviceError e){getSharedPreferences("libraryJob",MODE_PRIVATE).edit().clear().apply();throw e;}
    }
    private void rememberJob(ProtocolClient.LibraryJob job)throws IOException{boolean saved=getSharedPreferences("libraryJob",MODE_PRIVATE).edit().putBoolean("pending",true).putString("device",deviceLabel).putInt("id",job.id).putInt("op",job.operation).putInt("index",job.index).putLong("crc",job.crc).commit();if(!saved)throw new IOException("任务已启动，但手机未能保存任务编号，请核对曲库状态");}
    private void queryPendingJob(){SharedPreferences p=getSharedPreferences("libraryJob",MODE_PRIVATE);if(!p.getBoolean("pending",false)){message("没有保留的未完成任务");return;}if(!deviceLabel.equals(p.getString("device",""))){message("任务属于另一模块，请连接原模块后查询");return;}int id=p.getInt("id",-1),op=p.getInt("op",0),index=p.getInt("index",0);long crc=p.getLong("crc",0);cancel.set(false);int epoch=generation;task("查询曲库任务",()->{ProtocolClient c=client;ProtocolClient.LibraryCapabilities ext=c.libraryCapabilities();if(ext==null)throw new IOException("当前固件不支持任务查询");ProtocolClient.LibraryJob job=new ProtocolClient.LibraryJob(id<0?ext.latestJobId:id,op,index,crc);waitLibraryJob(c,job,epoch);});}
    private void waitLibraryJob(ProtocolClient c,ProtocolClient.LibraryJob job,int epoch)throws Exception{
        long deadline=SystemClock.elapsedRealtime()+180000;
        while(SystemClock.elapsedRealtime()<deadline){
            if(epoch!=generation||cancel.get())throw new IOException("已停止等待；琴端任务可能仍在运行。重连原模块后查询未完成任务。");
            ProtocolClient.LibraryJobStatus state=c.libraryJob(job);
            if(state.state==3){getSharedPreferences("libraryJob",MODE_PRIVATE).edit().clear().apply();throw new IOException("曲库操作失败："+ProtocolClient.flashJobError(state.error)+"；未宣称持久保存。");}
            if(state.state==2){if(job.operation==0&&!state.persisted)throw new IOException("任务完成但未确认持久保存，请核对目录");getSharedPreferences("libraryJob",MODE_PRIVATE).edit().clear().apply();ui(()->{if(epoch==generation){String text=(demo?"模拟结果：":"")+(job.operation==0?"已持久保存":job.operation==1?"已加载到RAM，未自动播放":"已删除")+String.format(Locale.ROOT," S%03d",job.index+1);libraryInfo.setText(text);progressText.setText(text);append(text);}});return;}
            ui(()->{if(epoch==generation){String text=job.operation==0?"正在保存Flash；尚未持久确认":"曲库任务进行中";libraryInfo.setText(text);progressText.setText(text);}});Thread.sleep(500);
        }
        throw new IOException("等待超时，任务结果未知。请保留任务编号并查询，勿重复发起擦写。");
    }
    private void playCommand(int cmd){int epoch=generation;task("发送播放控制",()->{ProtocolClient c=client;if(c==null)throw new IOException("未连接");c.command(cmd);ProtocolClient.Status s=c.status();ui(()->{if(epoch==generation)showStatus(s);});});}
    private void refreshStatus(){int epoch=generation;task("查询设备状态",()->{ProtocolClient c=client;if(c==null)throw new IOException("未连接");ProtocolClient.Status s=c.status();ui(()->{if(epoch==generation)showStatus(s);});});}
    private void showStatus(ProtocolClient.Status s){String state=s.state==1?"播放中":s.state==2?"已暂停":"已停止";position.setText((demo?"模拟设备 · ":"")+state+" · "+s.position+" ms\n曲谱"+(s.songValid?"有效":"无效")+" · 上传"+(s.uploading?"进行中":"空闲")+" · 最近错误 0x"+Integer.toHexString(s.lastError));append("状态已确认："+state+"，"+s.position+" ms");}
    private void message(String text){new AlertDialog.Builder(this).setMessage(text).setPositiveButton("知道了",null).show();}
    private Button performanceButton(String text,Runnable action){Button b=button(text,action,true);performanceButtons.add(b);return b;}
    private void buildPerformanceUi(){
        label("键位自定义",20,ink);mapInfo=label("读取琴端配置后编辑。每键可固定音色或跟随面板；应用前请松开全部琴键。",13,muted);
        page.addView(performanceButton("读取琴端键位",()->task("读取键位",()->{KeyMap m=client.readKeyMap();ProtocolClient.KeyMapStatus s=client.keyMapStatus();ui(()->{editedMap=m;showMapKey();mapInfo.setText("已读取设备配置，版本 "+s.version+"；启动状态 "+(s.flags&3)+"（1有效、2损坏回退、3容量不支持）");});})));
        mapBoard=new Spinner(this);setItems(mapBoard,new String[]{"PCB 1","PCB 2","PCB 3"});page.addView(mapBoard);
        mapKey=new Spinner(this);String[] keys=new String[12];for(int k=0;k<12;k++)keys[k]="琴键 "+(k+1)+" / CH"+String.format(Locale.ROOT,"%02d",k);setItems(mapKey,keys);page.addView(mapKey);
        mapPitch=new Spinner(this);String[] pitches=new String[88];String[] names={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};for(int k=0;k<88;k++){int n=k+21;pitches[k]=names[n%12]+(n/12-1)+" / MIDI "+n;}setItems(mapPitch,pitches);page.addView(mapPitch);
        mapTone=new Spinner(this);String[] tones=new String[17];tones[0]="跟随全局音色";for(int k=0;k<16;k++)tones[k+1]=Timbres.NAMES[k];setItems(mapTone,tones);page.addView(mapTone);
        AdapterView.OnItemSelectedListener select=new AdapterView.OnItemSelectedListener(){public void onNothingSelected(AdapterView<?> p){}public void onItemSelected(AdapterView<?> p,View v,int n,long id){showMapKey();}};mapBoard.setOnItemSelectedListener(select);mapKey.setOnItemSelectedListener(select);
        page.addView(performanceButton("暂存当前键的编辑",()->{if(editedMap==null){message("请先读取琴端配置");return;}int key=mapBoard.getSelectedItemPosition()*12+mapKey.getSelectedItemPosition();int t=mapTone.getSelectedItemPosition();editedMap=editedMap.with(key,mapPitch.getSelectedItemPosition()+21,t==0?31:t-1);mapInfo.setText("已暂存键 "+(key+1)+"；点击应用后琴端才会生效。");}));
        row(performanceButton("应用整组键位",()->{if(editedMap==null){message("请先读取琴端配置");return;}final KeyMap m=editedMap;task("应用键位",()->{client.applyKeyMap(m);ui(()->mapInfo.setText("已应用并回读核对；尚未保存到Flash。"));});}),performanceButton("恢复默认并应用",()->task("恢复默认键位",()->{client.defaultKeyMap();KeyMap m=client.readKeyMap();ui(()->{editedMap=m;showMapKey();mapInfo.setText("默认键位已应用；需要掉电保留请另点保存。");});})));
        row(performanceButton("保存当前配置到Flash",()->task("保存键位",()->{KeyMap m=client.readKeyMap();pendingMapCrc=m.crc();pendingMapJob=client.saveKeyMap(m);ui(()->mapInfo.setText("保存任务已接受，编号 "+pendingMapJob+"；请查询结果确认。"));})),performanceButton("查询键位保存结果",()->task("查询键位保存",()->{ProtocolClient.KeyMapStatus s=client.keyMapStatus();if(pendingMapJob>=0&&(s.job!=pendingMapJob||s.savedCrc!=pendingMapCrc))throw new IOException("保存任务标识不匹配，不能确认本次保存");ui(()->mapInfo.setText("任务 "+s.job+"："+(s.state==2?"Flash保存及读回校验成功":s.state==1?"进行中":s.state==3?"失败，错误 "+s.error:"尚无任务")));})));
        label("演奏录制与回传",20,ink);recordInfo=label("录制手动演奏，最多4096音符或1小时。断开蓝牙仍继续；琴端复位会丢失RAM录制。",13,muted);
        row(performanceButton("开始录制",()->new AlertDialog.Builder(this).setMessage("开始新录制将覆盖琴端上一段RAM录制。请先导出需要保留的内容，并松开全部琴键。").setNegativeButton("取消",null).setPositiveButton("开始",(d,w)->task("开始录制",()->{long id=client.startRecording();ui(()->recordInfo.setText("正在录制，编号 "+id+"；琴端也可停止。"));})).show()),performanceButton("停止录制",()->task("停止录制",()->{client.stopRecording();ui(()->recordInfo.setText("已请求停止；稍后刷新，状态5表示可回传。"));})));
        row(performanceButton("刷新录制状态",()->task("录制状态",()->{ProtocolClient.RecordingStatus s=client.recordingStatus();ui(()->recordInfo.setText(s.text()));})),performanceButton("回传 / 继续回传",this::downloadPerformance));
        page.addView(button("将已回传录制导出MIDI",this::savePerformanceMidi,false));
        page.addView(performanceButton("清空琴端录制",()->new AlertDialog.Builder(this).setMessage("清空琴端RAM录制？手机已回传的数据仍保留。").setNegativeButton("取消",null).setPositiveButton("清空",(d,w)->task("清空录制",()->{ProtocolClient.RecordingStatus s=client.recordingStatus();client.clearRecording(s.id);ui(()->recordInfo.setText("琴端录制已清空。"));})).show()));
        label("MIDI保存音符与起音音色，不保存混响、颤音和松键尾音。外部播放器使用GM近似；多端口还原取决于播放器支持。超过16声部或单音65535ms仍可导出，重新导入琴端时会明确报超限。",13,muted);
    }
    private void showMapKey(){if(editedMap==null||mapBoard==null)return;int k=mapBoard.getSelectedItemPosition()*12+mapKey.getSelectedItemPosition();mapPitch.setSelection(editedMap.pitch(k)-21);mapTone.setSelection(editedMap.timbre(k)==31?0:editedMap.timbre(k)+1);}
    private void downloadPerformance(){cancel.set(false);task("录制回传",()->{ProtocolClient.RecordingStatus s=client.recordingStatus();if(s.state!=5)throw new IOException("请先停止录制并等候校验完成（状态5）");if(recordingDownload==null||!recordingDownload.matches(s))recordingDownload=new PerformanceRecording(s);client.downloadRecording(recordingDownload,(n,total)->ui(()->recordInfo.setText("回传 "+n+" / "+total)),cancel);exportedMidi=recordingDownload.midi();ui(()->recordInfo.setText("回传及CRC校验完成，"+s.count+"个音符，可导出MIDI。"));});}
    private void savePerformanceMidi(){if(exportedMidi==null){message("请先完成录制回传");return;}Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("audio/midi").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,"Gaoshan-performance.mid");startActivityForResult(i,13);}
    @Override protected void onDestroy(){dead=true;disconnect();module.close();worker.shutdownNow();handler.removeCallbacksAndMessages(null);super.onDestroy();}
}
