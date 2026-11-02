"""Run one task with a Windows battery reserve; never stop unrelated processes.

Example: python scripts/run_power_guard.py -- python scripts/run_main_physical.py --name powered_run
The guard records state every 30 seconds and terminates only its launched process
tree at <=25% while discharging. Interrupted PNR is not a completed bitstream.
"""
import argparse,ctypes,datetime,json,os,subprocess,time
from pathlib import Path

class Power(ctypes.Structure):
    _fields_=[('ac',ctypes.c_ubyte),('flags',ctypes.c_ubyte),('percent',ctypes.c_ubyte),('reserved',ctypes.c_ubyte),('seconds',ctypes.c_ulong),('full_seconds',ctypes.c_ulong)]

def battery():
    p=Power()
    if not ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(p)):
        raise OSError('Cannot read battery status')
    return dict(ac=p.ac,percent=p.percent,seconds=p.seconds)

def main():
    a=argparse.ArgumentParser();a.add_argument('--minimum',type=int,default=25);a.add_argument('--status-only',action='store_true');a.add_argument('command',nargs=argparse.REMAINDER);x=a.parse_args()
    if x.status_only:print(json.dumps(battery()));return 0
    cmd=x.command[1:] if x.command[:1]==['--'] else x.command
    if not cmd:a.error('A command is required')
    root=Path(__file__).resolve().parents[1]
    out=root/'reports/adjustments_20261101/power';out.mkdir(parents=True,exist_ok=True)
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    path=out/(stamp+'.json');record=dict(command=cmd,minimum=x.minimum,pid=None,status='preflight',samples=[])
    def save():
        temp=path.with_suffix('.tmp');temp.write_text(json.dumps(record,indent=2));os.replace(temp,path)
    def sample():
        b=battery();b['utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();record['samples'].append(b);save();return b
    def low(b):return b['ac']!=1 and (b['percent']==255 or b['percent']<=x.minimum)
    if low(sample()):record['status']='deferred_low_or_unknown_battery';save();return 2
    proc=subprocess.Popen(cmd,cwd=root);record.update(pid=proc.pid,status='running');save()
    try:
        while proc.poll() is None:
            if low(sample()):
                record['status']='stopping_low_battery';save()
                subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
                proc.wait(timeout=30);record['status']='stopped_low_battery';save();return 2
            try:proc.wait(timeout=30)
            except subprocess.TimeoutExpired:pass
        record.update(status='finished',exit_code=proc.returncode);save();return proc.returncode
    except BaseException:
        record['status']='guard_interrupted';save()
        if proc.poll() is None:subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
        raise

if __name__=='__main__':raise SystemExit(main())
