"""Independent integer geometry and transaction tests for retained mono lag16 XY.

Writes reports only. No Pillow/Bresenham implementation is used by the oracle:
each line pixel is the exact rational position along its major axis, rounded
half away from its starting endpoint. Fixed seed supplies reproducible frames.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,math,os,random,re,subprocess,time
R=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--out-dir',type=Path,default=R/'reports/adjustments_20261101/xy');args=ap.parse_args();O=args.out_dir.resolve();O.mkdir(parents=True,exist_ok=True)
B=Path('C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin')
env=os.environ.copy();env['PATH']=str(B)+os.pathsep+env['PATH']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def line(a,b):
 dx=b[0]-a[0];dy=b[1]-a[1];m=max(abs(dx),abs(dy))
 if not m:return [a]
 def q(v,i):return (1 if v>=0 else -1)*((2*i*abs(v)+m)//(2*m))
 return [(a[0]+q(dx,i),a[1]+q(dy,i)) for i in range(m+1)]
def bitmap(w):
 ps=[(32+w[k]//4,31-w[k-4]//4) for k in range(4,128)]
 bits=[0]*4096
 for a,b in zip(ps,ps[1:]):
  for x,y in line(a,b):assert 0<=x<64 and 0<=y<64;bits[y*64+x]=1
 return bits
rng=random.Random(0x16_5916)
waves=[[0]*128,[127]*128,[-128]*128,[-128,127]*64,[0,127,0,-128]*32,
 [round(127*math.sin(2*math.pi*k/32)) for k in range(128)],
 [rng.randrange(-128,128) for k in range(128)],list(range(-128,128,2))]
waves += [[rng.randrange(-128,128) for k in range(128)] for f in range(56)]
(O/'waves.hex').write_text(''.join(f'{v&255:02x}\n' for w in waves for v in w))
(O/'maps.hex').write_text(''.join(f'{v:x}\n' for w in waves for v in bitmap(w)))

kernel=r'''`timescale 1ns/1ps
module tb_xy_geometry;
 reg clk=0,rst=1,tick=0,start=0,ren=0;always #5 clk=~clk;
 reg [1023:0] wave=0;reg [5:0] rx=0,ry=0;wire pixel,ready;
 lissajous_plot dut(clk,rst,tick,start,wave,ren,rx,ry,pixel,ready);
 integer checks=0,segments=0,draws=0,maxerr=0,seed=32'h165916;
 task segment(input integer ax,ay,bx,by);
 integer dx,dy,m,n,ex,ey,qx,qy,guard;begin
  dx=bx-ax;dy=by-ay;m=(dx<0?-dx:dx)>(dy<0?-dy:dy)?(dx<0?-dx:dx):(dy<0?-dy:dy);
  @(negedge clk);dut.state=3;dut.first=0;dut.x0=ax;dut.y0=ay;dut.x1=bx;dut.y1=by;dut.point_index=127;dut.build_bank=1;
  @(negedge clk);n=0;guard=0;
  while(dut.state==4 && guard<66)begin
   if(m==0)begin ex=ax;ey=ay;end else begin
    qx=(2*n*(dx<0?-dx:dx)+m)/(2*m);qy=(2*n*(dy<0?-dy:dy)+m)/(2*m);
    ex=ax+(dx<0?-qx:qx);ey=ay+(dy<0?-qy:qy);
   end
   checks++;if(dut.x0!==6'(ex)||dut.y0!==6'(ey))$fatal(1,"integer rational line differs (%0d,%0d)->(%0d,%0d) n%0d expected%0d,%0d actual%0d,%0d",ax,ay,bx,by,n,ex,ey,dut.x0,dut.y0);
   checks++;if(dut.waddr!==12'(ey*64+ex))$fatal(1,"write address differs");
   if($signed(dut.err)>maxerr)maxerr=$signed(dut.err);if(-$signed(dut.err)>maxerr)maxerr=-$signed(dut.err);
   @(posedge clk);#1;checks++;if(dut.bank1[ey*64+ex]!==1'b1)$fatal(1,"draw store failed");
   @(negedge clk);n++;guard++;draws++;
  end
  checks++;if(guard>64||n!=m+1||dut.state!=5)$fatal(1,"line not bounded");segments++;
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  // Exhaust every absolute delta0..63 and all four directions at the corners.
  for(integer dx=0;dx<64;dx++)for(integer dy=0;dy<64;dy++)for(integer d=0;d<4;d++)
   segment(d[0]?63:0,d[1]?63:0,d[0]?63-dx:dx,d[1]?63-dy:dy);
  // Also translate endpoints throughout the bitmap; deterministic random seed.
  for(integer s=0;s<8192;s++)segment($unsigned($random(seed))%64,$unsigned($random(seed))%64,$unsigned($random(seed))%64,$unsigned($random(seed))%64);
  // Every raw signed byte pair traverses actual LOAD conversion.
  for(integer a=0;a<256;a++)for(integer b=0;b<256;b++)begin
   @(negedge clk);dut.state=2;dut.point_index=4;dut.points=0;dut.points[32+:8]=a;dut.points[0+:8]=b;
   @(negedge clk);checks++;if(dut.x1!==6'(((a+128)%256)/4)||dut.y1!==6'(63-((b+128)%256)/4))$fatal(1,"signed coordinate mapping differs raw%0d,%0d",a,b);
  end
  $display("PASS tb_xy_geometry checks=%0d segments=%0d draw_pixels=%0d maximum_abs_error=%0d signed_pairs=65536",checks,segments,draws,maxerr);$finish;
 end
 initial begin #30000000;$fatal(1,"geometry timeout");end
endmodule
'''

frames=r'''`timescale 1ns/1ps
module tb_xy_frames;
 reg clk=0,rst=1,tick=0,start=0,ren=0;always #5 clk=~clk;
 reg [1023:0] wave=0;reg [5:0] rx=0,ry=0;wire pixel,ready;
 lissajous_plot dut(clk,rst,tick,start,wave,ren,rx,ry,pixel,ready);
 reg [7:0] inputs[0:8191];reg maps[0:262143];reg [4095:0] outdir,path;
 integer checks=0,builds=0,published=-1,job=-1,seed=32'h165916;
 reg expected_ready=0;reg monitor=0;reg expected_pixel;reg commit,old_bank;integer old_state;
 always @(posedge clk)begin
  if(monitor)begin
   expected_pixel=ren&&expected_ready?maps[published*4096+integer'(ry)*64+rx]:0;
   old_state=dut.state;commit=!rst&&dut.state==5&&tick;old_bank=dut.display_bank;
   if(rst)begin expected_ready=0;published=-1;end
   else if(commit)begin expected_ready=1;published=job;end
   #1;checks++;if(pixel!==expected_pixel)$fatal(1,"synchronous foreground read differs state%0d frame%0d xy%0d,%0d",old_state,published,rx,ry);
   checks++;if(ready!==expected_ready)$fatal(1,"ready differs");
   checks++;if(!rst&&!commit&&dut.display_bank!==old_bank)$fatal(1,"bank changed away from completed frame tick");
   checks++;if(!rst&&expected_ready&&dut.wen&&dut.build_bank==dut.display_bank)$fatal(1,"drawing into visible bank");
  end
 end
 task load(input integer f);begin for(integer k=0;k<128;k++)wave[k*8+:8]=inputs[f*128+k];end endtask
 task scan;begin
  ren=1;for(integer p=0;p<4096;p++)begin @(negedge clk);rx=p%64;ry=p/64;end
  @(negedge clk);ren=0;
 end endtask
 task build(input integer f,input integer concurrent);
 integer elapsed;begin
  @(negedge clk);load(f);job=f;start=1;tick=concurrent;
  @(negedge clk);start=0;tick=0;load((f+1)%64); // mutate live input after capture
  elapsed=0;
  while(dut.state!=5&&elapsed<13000)begin
   // Deliberate pulses while CLEAR/LOAD/SETUP/DRAW must be ignored.
   ren=(elapsed%3)!=0;rx=$random(seed);ry=$random(seed);
   tick=elapsed%113==0;start=elapsed%127==0;
   @(negedge clk);elapsed++;
  end
  tick=0;start=0;ren=0;checks++;if(dut.state!=5)$fatal(1,"build exceeded bound");
  checks++;if(dut.points!=={<<8{wave}})begin end // input snapshot tested by full bitmap below
  builds++;
 end endtask
 task publish;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
 initial begin
  if(!$value$plusargs("OUT=%s",outdir))$fatal(1,"missing output directory");
  $sformat(path,"%0s/waves.hex",outdir);$readmemh(path,inputs);$sformat(path,"%0s/maps.hex",outdir);$readmemh(path,maps);
  repeat(3)@(negedge clk);rst=0;monitor=1;
  for(integer f=0;f<64;f++)begin
   build(f,0);
   // No publication until a frame tick, including full scans of prior buffer.
   scan();publish();scan();
  end
  // Publish and start the next build together: old front becomes new back.
  build(3,0);
  @(negedge clk);load(4);tick=1;start=1;job=3;
  @(negedge clk);tick=0;start=0;job=4;
  wait(dut.state==5);@(negedge clk);scan();publish();scan();
  // Reset in every control phase; no stale ready or bitmap after restart.
  for(integer stage=1;stage<=5;stage++)begin
   @(negedge clk);load(6);job=6;start=1;@(negedge clk);start=0;
   wait(dut.state==stage);@(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;
   build(0,0);publish();scan();
  end
  // Ordinary silence is one center point (x32,y31), not an old full curve.
  checks++;for(integer p=0;p<4096;p++)if(maps[p]!==1'(p==31*64+32))$fatal(1,"zero oracle center differs");
  ren=0;repeat(3)@(negedge clk);checks++;if(pixel!==0)$fatal(1,"disabled read emits pixel");
  $display("PASS tb_xy_frames checks=%0d builds=%0d random_frames=56 delay_snapshot_points=4",checks,builds);$finish;
 end
 initial begin #40000000;$fatal(1,"frame interleave timeout");end
endmodule
'''
# Icarus does not implement all streaming concatenations; remove unused marker.
frames=frames.replace('  checks++;if(dut.points!=={<<8{wave}})begin end // input snapshot tested by full bitmap below\n','')
files=[R/'src/lissajous_plot.sv',Path(__file__).resolve()]
hashes={str(p.relative_to(R)):sha(p) for p in files};results=[];start_time=time.monotonic()
for name,tb in [('geometry',kernel),('frames',frames)]:
 p=O/(name+'.sv');p.write_text(tb,encoding='utf-8');cmd=[str(B/'iverilog.exe'),'-g2012','-s','tb_xy_'+name,'-o',(O/(name+'.vvp')).as_posix(),(R/'src/lissajous_plot.sv').as_posix(),p.as_posix()]
 c=subprocess.run(cmd,cwd=R,env=env,capture_output=True,text=True,encoding='utf-8');(O/(name+'_compile.log')).write_text(c.stdout+c.stderr);assert c.returncode==0,c.stderr
 c=subprocess.run([str(B/'vvp.exe'),(O/(name+'.vvp')).as_posix(),'+OUT='+O.as_posix()],cwd=R,env=env,capture_output=True,text=True,encoding='utf-8',timeout=180)
 output=c.stdout+c.stderr;(O/(name+'.log')).write_text(output);print(output,flush=True)
 results.append(dict(name=name,passed=c.returncode==0 and 'PASS tb_xy_'+name in output,checks=int(re.search(r'checks=(\d+)',output)[1]) if 'PASS ' in output else 0,compile_command=cmd,output=output,test_sha256=sha(p)))
 if not results[-1]['passed']:break
assert all(sha(R/n)==h for n,h in hashes.items()),'Source changed during tests'
report=dict(created_at=datetime.datetime.now().astimezone().isoformat(),passed=all(x['passed'] for x in results) and len(results)==2,source_sha256=hashes,total_checks=sum(x['checks'] for x in results),results=results,oracle='Independent exact integer rational major-axis positions, half away from start; waveform x=32+floor(signedbyte/4), y=31-floor(lag4/4)',fixture_sha256={n:sha(O/n) for n in ['waves.hex','maps.hex']},frames=len(waves),seconds=round(time.monotonic()-start_time,3),sta_passed=False,hardware_tested=False)
(O/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps({'passed':report['passed'],'total_checks':report['total_checks'],'seconds':report['seconds']}))
if not report['passed']:raise SystemExit(1)
