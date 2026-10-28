"""Parse actual Gowin STA sections; no construction or programming side effects."""
import argparse,json,re
from pathlib import Path

def inspect(path):
 t=Path(path).read_text(encoding='utf-8',errors='replace');body=t.split('Note:Core Timing Report')[-1];result={}
 result['counts']={k:int(m[1]) if (m:=re.search(r'<Numbers of '+k+r' Violated Endpoints>:(\d+)',body)) else None for k in ['Setup','Hold']}
 f=body.split('2.3 Max Frequency Summary')[-1].split('2.4 Total Negative Slack Summary')[0]
 result['fmax']={m[1]:{'target':float(m[2]),'actual':float(m[3])} for m in re.finditer(r'\d+\s+(\w+)\s+([\d.]+)\(MHz\)\s+([\d.]+)\(MHz\)',f)}
 tn=body.split('2.4 Total Negative Slack Summary',1)[1].split('3. Timing Details',1)[0]
 result['tns']=[dict(clock=m[1],analysis=m[2],tns=float(m[3]),endpoints=int(m[4])) for m in re.finditer(r'^\s*(\w+)\s+(setup|hold)\s+(-?[\d.]+)\s+(\d+)\s*$',tn,re.M)]
 paths={}
 for section in re.split(r'(?=3\.1\.\d[^\n]*Paths Table)',body):
  if not section.startswith('3.1.'):continue
  title=section.splitlines()[0];part=section.split('3.2 Minimum Pulse Width Table')[0]
  rows=[]
  for line in part.splitlines():
   m=re.match(r'^\s*(\d+)\s+(-?\d+\.\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+',line)
   if m:rows.append(dict(number=int(m[1]),slack=float(m[2]),source=m[3],endpoint=m[4],from_clock=m[5],to_clock=m[6]))
  if rows:paths[title]=rows
 result['path_tables']=paths
 result['internal_wns']={}
 for rows in paths.values():
  for row in rows:
   if 'Setup' not in next((title for title,rr in paths.items() if rr is rows),''):continue
   c=row['from_clock'].split(':')[0]
   if c in ['ref_clk','audio_clk','pixel_clk'] and c==row['to_clock'].split(':')[0]:
    result['internal_wns'][c]=min(result['internal_wns'].get(c,1e9),row['slack'])
 pw=body.split('3.2 Minimum Pulse Width Table',1)[1].split('3.3 Timing Report',1)[0] if '3.2 Minimum Pulse Width Table' in body else ''
 result['pulse_width_slacks']=[float(m[1]) for m in re.finditer(r'^\s*\d+\s+(-?\d+\.\d+)\s+\d+\.\d+\s+\d+\.\d+\s+',pw,re.M)]
 result['pulse_width_pass']=all(x>=0 for x in result['pulse_width_slacks'])
 result['all_reported_paths_nonnegative']=all(row['slack']>=0 for rows in paths.values() for row in rows)
 result['internal_margin_pass']=all(result['internal_wns'].get(c,-1)>=.5 for c in ['ref_clk','audio_clk','pixel_clk'])
 result['setup_hold_pass']=result['counts']=={'Setup':0,'Hold':0} and all(row['tns']==0 and row['endpoints']==0 for row in result['tns'])
 return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('report');p.add_argument('--output');a=p.parse_args();r=inspect(a.report)
 if a.output:Path(a.output).write_text(json.dumps(r,indent=2),encoding='utf-8')
 print(json.dumps({k:v for k,v in r.items() if k!='path_tables'},indent=2))
