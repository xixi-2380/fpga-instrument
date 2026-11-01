"""Merged display: gesture acceptance, all selected pages, frame/pixel alignment.

This is an RTL/software render using behavioral inputs, not panel/STA evidence.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,sys,math

P=argparse.ArgumentParser();P.add_argument('--tool-bin',type=Path,required=True);P.add_argument('--out-dir',type=Path,required=True);a=P.parse_args()
R=Path(__file__).resolve().parents[1];O=a.out_dir.resolve();O.mkdir(parents=True,exist_ok=True);B=a.tool_bin.resolve();env=os.environ.copy();env['PATH']=str(B)+os.pathsep+env['PATH']
results=[]
def run(name,top,files,source,timeout=900):
 tb=O/(name+'.sv');tb.write_text(source,encoding='utf-8');paths=[R/f for f in files]+[tb]
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
 cmd=[str(B/'iverilog.exe'),'-g2012','-grelative-include','-I'+(R/'src').as_posix(),'-I'+(R/'sim').as_posix(),'-s',top,'-o',(O/(name+'.vvp')).as_posix()]+[p.as_posix() for p in paths]
 c=subprocess.run(cmd,cwd=R,env=env,capture_output=True,text=True,encoding='utf-8');(O/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
 c=subprocess.run([str(B/'vvp.exe'),(O/(name+'.vvp')).as_posix(),'+OUT='+O.as_posix()],cwd=R,env=env,capture_output=True,text=True,encoding='utf-8',timeout=timeout);log=c.stdout+c.stderr;(O/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True);assert c.returncode==0 and 'PASS '+top in log,log
 assert all(hashlib.sha256(p.read_bytes()).hexdigest()==hashes[str(p)] for p in paths)
 results.append(dict(name=name,passed=True,checks=int(re.search(r'checks=(\d+)',log)[1]),source_sha256=hashes,output=log))

touch=r'''`timescale 1ns/1ps
module tb_merged_touch;
reg clk=0,rst=1,enabled=1,valid=1,ready=1,error=0,down=0;always #5 clk=~clk;
reg [3:0] count=1;reg [15:0] x=0,y=0,rx=800,ry=480;reg [1:0] fx=2;
reg menu=0,more=0,ultra=0,harp=0,sens=0;wire av;wire[6:0] act;
`include "config/ui_layout.svh"
ui_touch_actions dut(clk,rst,enabled,valid,ready,error,down,count,x,y,rx,ry,fx,menu,av,act,more,ultra,harp,sens);
integer checks=0,events=0;always @(posedge clk)begin #0.001;if(av)events++;end
task press(input [6:0] want,input integer xx,yy);
integer prior_events;begin
 @(negedge clk);down=0;repeat(2)@(negedge clk);x=xx;y=yy;prior_events=events;down=1;
 repeat(2)@(negedge clk);checks++;
 if(want==UI_NONE)begin if(events!=prior_events)$fatal(1,"unexpected action %0d at %0d,%0d",act,xx,yy);end
 else if(events!=prior_events+1 || act!==want)$fatal(1,"wanted %0d got %0d events%0d",want,act,events-prior_events);
 repeat(15)@(negedge clk);checks++;if(events!=prior_events+(want!=UI_NONE))$fatal(1,"held touch repeated");
end endtask
task button(input[6:0] want);reg[43:0] q;begin q=ui_rect(want);press(want,q[43:33]+q[21:11]/2,q[32:22]+q[10:0]/2);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(integer page=0;page<6;page++)begin
  menu=page>=1;more=page==2;ultra=page==3;sens=page==4;harp=page==5;if(harp)menu=0;
  button(UI_THEME);button(UI_LANGUAGE);button(UI_VIEW);button(UI_EGG);
  case(page)
   0:begin button(UI_MODE);button(UI_HARP_OPEN);end
   1:begin for(integer i=64;i<72;i++)button(i);button(UI_TONE_PAGE);button(UI_ECHO);button(UI_ROOM);button(UI_TREMOLO);button(UI_FX);button(UI_VOLUME_DOWN);button(UI_VOLUME_UP);button(UI_SENSITIVITY);button(UI_ULTRA_OPEN);button(UI_OPEN_MORE);end
   2:begin button(UI_SONG_PREV);button(UI_SONG_NEXT);button(UI_SONG_LOAD);button(UI_SONG_PLAY);button(UI_SONG_PAUSE);button(UI_SONG_RESUME);button(UI_SONG_STOP);button(UI_SONG_SAVE);button(UI_SONG_DELETE);button(UI_FLASH_INFO);button(UI_MORE_BACK);end
   3:begin button(UI_ULTRA_TOGGLE);button(UI_SENS_DOWN);button(UI_SENS_UP);button(UI_MIN_DOWN);button(UI_MIN_UP);button(UI_MAX_DOWN);button(UI_MAX_UP);button(UI_ULTRA_BACK);end
   4:begin button(UI_GSR_DOWN);button(UI_GSR_UP);button(UI_KOR_DOWN);button(UI_KOR_UP);button(UI_SENS_APPLY);button(UI_SENS_DEFAULT);button(UI_SENS_BACK);end
   5:begin button(UI_CHORUS);button(UI_CHORUS_MIX);button(UI_CHORUS_DEPTH);button(UI_CHORUS_RATE);button(UI_HARP_TONE);button(UI_HARP_BACK);press(UI_NONE,400,390);press(UI_NONE,112,200);end
  endcase
 end
 // Error / missing calibration / multi-touch cannot arm a stale held contact.
 error=1;press(UI_NONE,720,40);error=0;repeat(4)@(negedge clk);checks++;if(av)$fatal(1,"error contact rearmed while held");
 rx=0;press(UI_NONE,720,40);rx=800;count=2;press(UI_NONE,720,40);count=1;
 $display("PASS tb_merged_touch checks=%0d events=%0d",checks,events);$finish;
end
endmodule'''
run('touch','tb_merged_touch',['src/ui_touch_actions.sv'],touch)

render=r'''`timescale 1ns/1ps
module tb_merged_pixels;
reg clk=0,rst=1,fs=0,valid=0;always #1 clk=~clk;
reg[1279:0] data=0;reg[145:0] more=0;reg[63:0] perf=0;reg[512:0] analysis=0;
reg[10:0] x=0,y=0;reg de=0,hs=0,vs=0;wire[23:0] rgb;wire od,oh,ov;
rgb_ui_renderer dut(clk,rst,fs,valid,data,x,y,de,hs,vs,rgb,od,oh,ov,analysis,1'b1,more,perf);
reg[8:0] ed=0,eh=0,ev=0;integer checks=0,pixels=0,fd=0;reg capture=0;reg[8191:0] out;reg[8191:0] name;reg[1279:0] prior;
always @(posedge clk)begin
 #0.001;
 if(rst)begin ed=0;eh=0;ev=0;end
 else begin
  ed={ed[7:0],de};eh={eh[7:0],hs};ev={ev[7:0],vs};checks++;
  if({od,oh,ov}!=={ed[8],eh[8],ev[8]})$fatal(1,"RGB/control pixel latency differs at%0d",checks);
  if(od && (^rgb===1'bx))$fatal(1,"visible RGB containsX");
  if(capture && od)begin $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);pixels++;end
 end
end
task tick;begin @(negedge clk);end endtask
task commit;begin fs=1;tick();fs=0;repeat(14)tick();end endtask
task setup(input integer theme,zh,page,view);
begin
 data=0;more=0;perf=0;data[15]=1;data[49]=1;data[50]=1;data[51]=1;data[1209:1208]=theme;data[1210]=zh;data[1212:1211]=view;
 data[1132]=1;data[1131:1112]=20'h00137;data[5:0]=12;data[1207]=1;data[13:12]=1;data[60:54]=70;data[30:24]=25;data[37:31]=40;data[44:38]=50;data[48:45]=5;data[1169:1167]=7;data[1183:1172]=12'h150;
 data[79:64]=16'ha55a;data[1203:1184]=20'ha55aa;data[1206:1204]=7;data[87:80]=180;
 for(integer k=0;k<128;k++)data[88+k*8+:8]=$signed(((k%32)-16)*6);
 for(integer k=0;k<64;k++)analysis[k*8+:8]=32+k;analysis[512]=1;
 case(page)
  1:data[20]=1;
  2:begin data[20]=1;more[81]=1;more[5]=1;more[58]=1;more[4:0]=9;end
  3:begin data[20]=1;data[1166]=1;data[1165]=1;data[1164:1162]=3;data[1161:1155]=10;data[1154:1148]=50;data[1147:1145]=2;data[1144:1133]=12'h027;end
  4:begin data[20]=1;data[1228]=1;data[1216:1213]=2;data[1224:1217]=4;data[1227]=1;end
  5:begin perf[0]=1;perf[1]=1;perf[4:2]=2;perf[6:5]=2;perf[8:7]=1;perf[20:9]=12'ha55;end
 endcase
 commit();
end endtask
task image(input integer id);
integer step;begin
 step=id==0?1:2;
 $sformat(name,"%0s/page_%0d.ppm",out,id);fd=$fopen(name,"wb");if(fd==0)$fatal(1,"image open failed");$fwrite(fd,"P6\n%0d %0d\n255\n",800/step,480/step);pixels=0;capture=1;
 for(integer yy=0;yy<480;yy=yy+step)begin
  for(integer xx=0;xx<800;xx=xx+step)begin x=xx;y=yy;de=1;hs=xx<4;vs=yy<2;tick();end
  de=0;hs=0;repeat(12)tick();
 end
 de=0;vs=0;repeat(12)tick();capture=0;$fclose(fd);if(pixels!=384000/(step*step))$fatal(1,"pixel count%0d",pixels);
end endtask
initial begin
 if(!$value$plusargs("OUT=%s",out))$fatal(1,"missing output dir");repeat(3)tick();rst=0;valid=1;
 setup(0,0,0,0);prior=data;data[1209:1208]=3;data[1210]=1;repeat(30)tick();checks++;if(dut.state!==prior)$fatal(1,"snapshot changed before frame start");commit();if(dut.state!==data)$fatal(1,"snapshot not committed atomically");
 setup(0,0,0,0);more[81]=1;commit();checks++;if(dut.library_page)$fatal(1,"stale library status overrode performance page");
 for(integer t=0;t<4;t++)begin setup(t,0,0,0);image(t*2);setup(t,1,0,0);image(t*2+1);end
 setup(0,1,0,1);image(8);
 setup(0,1,0,2);repeat(22000)tick();commit();image(9);
 for(integer page=1;page<=5;page++)begin setup(0,1,page,0);image(9+page);end
 $display("PASS tb_merged_pixels checks=%0d images=15 full_resolution=1 half_resolution=14",checks);$finish;
end
endmodule'''
run('pixels','tb_merged_pixels',['src/rgb_ui_renderer.sv','src/ui_theme_art.sv','src/lissajous_plot.sv'],render)

files=[R/'src'/name for name in ['rgb_display.sv','rgb_ui_renderer.sv','ui_theme_art.sv','audio_spectrum.sv','lissajous_plot.sv','ui_touch_actions.sv']]
files += list((R/'src/config').glob('ui*.svh'))+[R/'src/config/theme_storage.svh',R/'src/rom/theme_font.hex']
report=dict(tests=results,total_checks=sum(x['checks'] for x in results),images=15,behavioral_render=True,sta_passed=False,hardware_tested=False,source_sha256={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files})
(O/'validation.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print('Display validation saved',flush=True)
