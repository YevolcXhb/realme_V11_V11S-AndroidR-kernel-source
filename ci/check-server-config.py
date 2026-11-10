#!/usr/bin/env python3
"""Fail after olddefconfig if the requested server/USB profile was dropped."""
import sys
from pathlib import Path

def config(path):
    result={}
    for line in Path(path).read_text().splitlines():
        if line.startswith('CONFIG_') and '=' in line:
            key,value=line.split('=',1);result[key]=value
        elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
            result[line[2:-11]]='n'
    return result

def main():
    actual=config(sys.argv[1]);wanted=config(Path(__file__).with_name('server.config'))
    # Keep the vendor scheduler/ABI safeguards. The existing CI CRC check is still mandatory.
    wanted.update(CONFIG_SCHED_WALT='y',CONFIG_SCHED_HMP='y',CONFIG_MODVERSIONS='y',
                  CONFIG_PREEMPT='y',CONFIG_MODULE_SIG='y')
    failures=[f'{key}: wanted {value}, got {actual.get(key,"missing")}' for key,value in wanted.items() if actual.get(key)!=value]
    if failures:raise SystemExit('Server configuration validation failed:\n'+'\n'.join(failures))
    print(f'Server configuration validated: {len(wanted)} requirements; no CRC assertion made here.')
if __name__=='__main__':main()
