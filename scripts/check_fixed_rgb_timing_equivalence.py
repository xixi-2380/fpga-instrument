"""Compare PCB formatting and production raster prefetch against4a0ea05."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out-dir', required=True)
p.add_argument('--only', choices=['pcb', 'pixels'])
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
out = (root / a.out_dir).resolve()
out.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
bins = root / 'tools/mingw64/bin'
env['PATH'] = str(bins) + os.pathsep + env['PATH']
sources = {}
for module in ['pcb_debug_ui', 'rgb_ui_renderer']:
    f = root / 'src' / (module + '.sv')
    sources[f.relative_to(root).as_posix()] = hashlib.sha256(f.read_bytes()).hexdigest()
    old = subprocess.check_output(['git', 'show', '4a0ea05:src/' + module + '.sv'], cwd=root).decode('utf8')
    old = old.replace('module ' + module, 'module baseline_' + module, 1)
    for header in ['ui_layout.svh', 'rgb_led_config.svh']:
        old = old.replace('"config/' + header + '"', '"' + Path(os.path.relpath(root / 'src/config' / header, out)).as_posix() + '"')
    (out / ('baseline_' + module + '.sv')).write_text(old, encoding='utf8')

pcb = r'''
`timescale 1ns/1ps
module tb_format_equivalence;
 reg clk=0,rst=1,av=0;always #5 clk=~clk;
 reg [6:0] action=63;reg [1023:0] hw=0;reg [383:0] enc=0;reg [319:0] audio=0;
 wire [2591:0] actual,expected;wire ma,mb,pa,pb;wire [159:0] ca,cb;
 integer checks=0;reg [19:0] bcd;reg [17:0] binary;
 pcb_debug_ui dut(.clk(clk),.rst(rst),.ms_ce(1'b0),.menu_mode(1'b1),.mute_ack(1'b1),
 .action_valid(av),.action(action),.hardware_valid(1'b1),.hardware(hw),.encoder_diag(enc),
 .encoder_events(12'd0),.audio_status(audio),.display(actual),.display_visible(1'b1),
 .mute_request(ma),.page_active(pa),.control(ca));
 baseline_pcb_debug_ui old(.clk(clk),.rst(rst),.ms_ce(1'b0),.menu_mode(1'b1),.mute_ack(1'b1),
 .action_valid(av),.action(action),.hardware_valid(1'b1),.hardware(hw),.encoder_diag(enc),
 .encoder_events(12'd0),.audio_status(audio),.display(expected),.display_visible(1'b1),
 .mute_request(mb),.page_active(pb),.control(cb));
 task act(input [6:0] code);begin
  @(negedge clk);action=code;av=1;@(negedge clk);av=0;
  repeat(160)@(negedge clk);
  if(actual!==expected)$fatal(1,"PCB snapshot mismatch tab=%0d detail=%0d board=%0d actual=%h expected=%h",dut.tab,dut.detail,dut.board,actual,expected);
  checks++;
 end endtask
 always @(posedge clk)begin #1;
  if(!rst && {ma,pa,ca}!=={mb,pb,cb})$fatal(1,"Control behavior changed while formatting");
 end
 initial begin
  // Exhaust the entire17-bit converter input, including saturation above99999.
  for(integer n=0;n<131072;n++)begin
   bcd=0;binary=n>99999?99999:n;
   for(integer k=0;k<9;k++)begin bcd=dut.bcd_step2(bcd,binary[17:16]);binary=binary<<2;end
   if(dut.decimal_chars(bcd)!==old.decimal5(n))$fatal(1,"Decimal mismatch n=%0d",n);
   checks++;
  end
  repeat(3)@(negedge clk);rst=0;
  hw[905:904]=0;act(42);
  for(integer board=0;board<3;board++)begin
   if(board!=0)begin hw[905:904]=board;act(50);end
   if(dut.board!=board || old.board!=board)$fatal(1,"Board selector coverage failure");
   for(integer tab=0;tab<5;tab++)begin
    for(integer w=0;w<32;w++)hw[w*32+:32]=$urandom;
    for(integer w=0;w<12;w++)enc[w*32+:32]=$urandom;
    for(integer w=0;w<10;w++)audio[w*32+:32]=$urandom;
    hw[905:904]=board;audio[45]=0;audio[44:42]=0;audio[38]=0;audio[36]=0;
    act(7'(44+tab));
    for(integer detail=0;detail<3;detail++)act(62);
   end
  end
  $display("PASS tb_format_equivalence checks=%0d all17bit decimal values and60 PCB page snapshots",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"PCB equivalence timeout");end
endmodule
'''

pixels = r'''
`timescale 1ns/1ps
module tb_raster_equivalence;
 reg clk=0,rst=1,fs=0,de=0,hs=1,vs=1;always #5 clk=~clk;
 reg [10:0] x=0,y=0,rx=0,ry=0;reg rfs=0,rde=0,rhs=1,rvs=1;
 reg [1207:0] status=0;reg [145:0] more=0;reg [2591:0] pcb=0;reg [519:0] leds=0;
 wire [23:0] actual,expected;wire da,db,ha,hb,va,vb;wire [1023:0] waveform;
 wire [6:0] bin=(x-11'd32)>>2;
 wire signed [7:0] now_sample=waveform[bin*8+:8];
 wire signed [7:0] previous_sample=bin!=0?waveform[(bin-7'd1)*8+:8]:now_sample;
 reg signed [9:0] point_q=234,previous_q=234;
 integer checks=0,frames=0;
 // The actual rgb_display raster/prefetch register stage, with unchanged latency.
 always @(posedge clk)begin
  if(rst)begin rx<=0;ry<=0;rfs<=0;rde<=0;rhs<=1;rvs<=1;point_q<=234;previous_q<=234;end
  else begin
   rx<=x;ry<=y;rfs<=fs;rde<=de;rhs<=hs;rvs<=vs;
   point_q<=10'sd234-($signed(now_sample)>>>1);
   previous_q<=10'sd234-($signed(previous_sample)>>>1);
  end
 end
 rgb_ui_renderer #(.WAVE_PREFETCH(1)) dut(clk,rst,rfs,1'b1,status,rx,ry,rde,rhs,rvs,
 actual,da,ha,va,more,pcb,,leds,point_q,previous_q,waveform);
 baseline_rgb_ui_renderer old(clk,rst,rfs,1'b1,status,rx,ry,rde,rhs,rvs,
 expected,db,hb,vb,more,pcb,,leds);
 always @(posedge clk)begin #1;
  if(!rst)begin
   if({actual,da,ha,va}!=={expected,db,hb,vb})
    $fatal(1,"Raster mismatch scene=%0d x=%0d y=%0d actual=%h expected=%h",frames,rx,ry,actual,expected);
   checks++;
  end
 end
 task snapshot;begin
  @(negedge clk);de=0;fs=1;x=0;y=0;
  @(negedge clk);fs=0;repeat(8)@(negedge clk);
 end endtask
 task frame;begin
  for(integer yy=0;yy<480;yy++)for(integer xx=0;xx<800;xx++)begin
   @(negedge clk);x=xx;y=yy;de=1;hs=(xx%113)!=0;vs=(yy%127)!=0;
  end
  @(negedge clk);de=0;repeat(8)@(negedge clk);frames++;
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(integer scene=0;scene<9;scene++)begin
   status=0;more=0;pcb=0;leds=0;
   status[15]=1;status[60:54]=73;status[5:0]=32;status[1206:1204]=7;status[1169:1167]=7;
   status[30:24]=99;status[37:31]=42;status[44:38]=65;status[48:45]=4;status[61]=1;
   for(integer j=0;j<128;j++)status[88+j*8+:8]=$urandom;
   status[88+:8]=8'h80;status[96+:8]=8'h7f;
   case(scene)
    1,2,3:begin status[20]=1;status[22:21]=scene-1;status[1172]=1;end
    4:begin status[20]=1;status[1166]=1;status[1165]=1;status[1164:1162]=3;end
    5:begin status[20]=1;more[81]=1;more[79]=1;more[57:34]=24'hef4018;end
    6:begin status[20]=1;pcb[2560]=1;pcb[2564:2562]=4;for(integer w=0;w<80;w++)pcb[w*32+:32]=$urandom;end
    7:begin status[20]=1;leds[519:504]={1'b1,1'b1,2'd3,3'd7,7'd73,2'd2};for(integer w=0;w<21;w++)leds[w*24+:24]=$urandom;end
    8:status[19]=1;
    default:begin end
   endcase
   snapshot;frame;
  end
  // Clipping/blanking outside800x480, including discontinuous coordinates.
  status=0;snapshot;
  for(integer n=0;n<4096;n++)begin
   @(negedge clk);x=$urandom;y=$urandom;de=$urandom;hs=$urandom;vs=$urandom;
  end
  @(negedge clk);de=0;repeat(10)@(negedge clk);
  $display("PASS tb_raster_equivalence checks=%0d full_frames=%0d",checks,frames);$finish;
 end
 initial begin #50000000;$fatal(1,"Raster equivalence timeout");end
endmodule
'''

cases = [('pcb', 'tb_format_equivalence', pcb, 'pcb_debug_ui'),
         ('pixels', 'tb_raster_equivalence', pixels, 'rgb_ui_renderer')]
results = []
for name, top, bench, module in cases:
    if a.only and name != a.only:
        continue
    directory = out / name
    directory.mkdir(exist_ok=True)
    tb = directory / (top + '.sv')
    tb.write_text(bench, encoding='utf8')
    image = directory / (top + '.vvp')
    cmd = [str(bins / 'iverilog.exe'), '-g2012', '-grelative-include', '-I' + (root / 'src').as_posix(),
           '-s', top, '-o', str(image), (root / 'src' / (module + '.sv')).as_posix(),
           (out / ('baseline_' + module + '.sv')).as_posix(), tb.as_posix()]
    c = subprocess.run(cmd, cwd=root, env=env, capture_output=True, text=True, encoding='utf8', errors='replace')
    (directory / 'compile.log').write_text(c.stdout + c.stderr, encoding='utf8')
    assert c.returncode == 0, c.stdout + c.stderr
    started = time.time()
    v = subprocess.run([str(bins / 'vvp.exe'), str(image)], cwd=root, env=env, capture_output=True,
                       text=True, encoding='utf8', errors='replace', timeout=2400)
    (directory / 'run.log').write_text(v.stdout + v.stderr, encoding='utf8')
    result = dict(case=name, passed=v.returncode == 0 and 'PASS ' + top in v.stdout,
                  seconds=round(time.time()-started, 3))
    print(json.dumps(result), v.stdout, flush=True)
    results.append(result)
    assert result['passed']
unchanged = all(hashlib.sha256((root / f).read_bytes()).hexdigest() == value for f, value in sources.items())
(out / 'validation.json').write_text(json.dumps(dict(passed=unchanged and all(v['passed'] for v in results),
                                                   source_hashes=sources, unchanged=unchanged, results=results), indent=2), encoding='utf8')
assert unchanged
