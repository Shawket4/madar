"""Build .shots/index.html: every dashboard screenshot grouped by area and page, newest first."""
import html, os, sys, time
root = sys.argv[1]
groups = {}
for dp, _, files in os.walk(root):
    for f in files:
        if not f.endswith('.png'): continue
        rel = os.path.relpath(os.path.join(dp, f), root)
        parts = rel.split(os.sep)
        area = parts[0]; page = '/'.join(parts[1:-1]) or '-'
        groups.setdefault(area, {}).setdefault(page, []).append((os.path.getmtime(os.path.join(dp, f)), rel))
out = ['<!doctype html><meta charset="utf-8"><title>Dashboard shots</title><style>',
 'body{font:14px -apple-system,system-ui,sans-serif;margin:0;background:#f1f3f3;color:#101820}',
 'header{position:sticky;top:0;background:#0d1a1e;color:#eef3f4;padding:12px 20px;display:flex;gap:16px;align-items:center;z-index:2}',
 'header input{flex:1;max-width:420px;padding:8px 10px;border-radius:8px;border:0}',
 'nav a{color:#9fd3db;margin-right:12px;text-decoration:none}',
 'h2{margin:28px 20px 6px} h3{margin:16px 20px 6px;font-size:13px;color:#4a5a62;font-weight:600}',
 '.grid{display:flex;flex-wrap:wrap;gap:12px;padding:0 20px}',
 'figure{margin:0;background:#fff;border:1px solid #dde4e6;border-radius:8px;padding:6px;width:300px}',
 'figure img{width:100%;height:190px;object-fit:contain;background:#e8eced;cursor:zoom-in;border-radius:4px}',
 'figcaption{font-size:11px;color:#4a5a62;word-break:break-all;margin-top:4px}',
 '#big{display:none;position:fixed;inset:0;background:rgba(0,0,0,.85);z-index:5;align-items:center;justify-content:center}',
 '#big img{max-width:95vw;max-height:95vh} </style>',
 f'<header><b>Flutter dashboard — {sum(len(v) for g in groups.values() for v in g.values())} screenshots</b>',
 '<input id=q placeholder="Filter: area, page, phone, ar, dark…" oninput="f()"><nav>' + ''.join(f'<a href="#{a}">{a}</a>' for a in sorted(groups)) + '</nav></header>']
for area in sorted(groups):
    out.append(f'<h2 id="{area}">{html.escape(area)}</h2>')
    for page in sorted(groups[area]):
        out.append(f'<h3>{html.escape(page)}</h3><div class=grid>')
        for _, rel in sorted(groups[area][page], key=lambda t: t[1]):
            out.append(f'<figure data-k="{html.escape(rel.lower())}"><img loading=lazy src="{html.escape(rel)}" onclick="z(this.src)"><figcaption>{html.escape(os.path.basename(rel))}</figcaption></figure>')
        out.append('</div>')
out.append('<div id=big onclick="this.style.display=\'none\'"><img id=bi></div><script>'
 'function z(s){bi.src=s;big.style.display="flex"}'
 'function f(){const q=document.getElementById("q").value.toLowerCase().split(/\\s+/).filter(Boolean);'
 'document.querySelectorAll("figure").forEach(e=>{e.style.display=q.every(w=>e.dataset.k.includes(w))?"":"none"})}</script>')
open(os.path.join(root, 'index.html'), 'w').write('\n'.join(out))
print('ok')
