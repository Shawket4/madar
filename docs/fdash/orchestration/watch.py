import json, os, sys, time, re
B = sys.argv[1]
runs = {'wf_686ad2aa-e8b':'FND','wf_db12a37b-11f':'sell','wf_8c2b3069-134':'menu','wf_0d419f82-0d7':'offers','wf_23e29823-8db':'reports','wf_2104ccb4-696':'inventory','wf_c6cd87d8-25a':'team','wf_122c9d5a-f73':'setup','wf_5fe344f3-f98':'admin'}
pos = {}; labels = {}
state = os.path.join(os.path.dirname(sys.argv[0]), 'watch.state.json')
try: pos = json.load(open(state))
except Exception: pos = {}
REF = re.compile(r'cargoclean|zshrc|did not do|not the .* task|has nothing to do with|I did not build|refus', re.I)
while True:
    for run, tag in runs.items():
        f = os.path.join(B, run, 'journal.jsonl')
        if not os.path.exists(f): continue
        with open(f) as h:
            h.seek(pos.get(run, 0)); data = h.read(); pos[run] = h.tell()
        for line in data.splitlines():
            try: e = json.loads(line)
            except Exception: continue
            if e.get('type') == 'started': labels[e.get('agentId')] = e.get('label') or ''
            if e.get('type') != 'result': continue
            r = e.get('result'); lab = e.get('label') or labels.get(e.get('agentId'), '?')
            if isinstance(r, dict):
                s = (r.get('summary') or r.get('verdict') or '')
                done = r.get('done')
                rows = f" rows={r.get('rowsCovered')}/{r.get('rowsTotal')}" if r.get('rowsTotal') else ''
            else:
                s, done, rows = str(r), None, ''
            milestone = tag == 'FND' or lab.split(':')[0] in ('scaffold', 'check', 'finish', 'commit')
            bad = done is False or (s and REF.search(s[:600]))
            if milestone or bad:
                print(f"[{tag}] {lab} done={done}{rows} :: {s[:170].replace(chr(10),' ')}", flush=True)
    json.dump(pos, open(state, 'w'))
    time.sleep(10)
