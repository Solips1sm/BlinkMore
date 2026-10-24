"""Build portable contact sheets and the interactive SVG study without dependencies."""
from pathlib import Path
import json, html, shutil, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent
base=json.loads((ROOT/'concepts.json').read_text())
refinements=[]
for path in sorted((ROOT/'refinements').glob('designer-*.json')):
    refinements.extend(json.loads(path.read_text()))
all_items=base+refinements
assert len({item['id'] for item in all_items})==len(all_items)
for item in all_items:
    p=ROOT/item['file']; node=ET.fromstring(p.read_text())
    assert node.attrib['viewBox']=='0 0 160 100',p
    for e in node.iter():
        assert e.tag.split('}')[-1] in {'svg','path','g','circle','ellipse','rect','line','polyline','polygon','defs','clipPath','mask'},(p,e.tag)
        assert not any(k.lower().startswith('on') or 'href' in k for k in e.attrib),(p,e.attrib)
(ROOT/'assets').mkdir(exist_ok=True)
for name in ['Comfortaa-Variable.woff2','Comfortaa-OFL.txt']:
    source=ROOT.parent.parent/'BlinkMore/Resources/UI/fonts'/name
    if source.is_file():shutil.copy2(source,ROOT/'assets'/name)
    else:assert (ROOT/'assets'/name).is_file()
css='''@font-face{font-family:Comfortaa;src:url(assets/Comfortaa-Variable.woff2) format("woff2");font-weight:300 700;font-display:block}*{box-sizing:border-box}body{margin:0;background:#e1e3e5;color:#1c1c1e;font:14px/1.45 -apple-system,BlinkMacSystemFont,system-ui,sans-serif}body.dark{background:#101012;color:#f2f2f7}h1,h2,h3,p{margin:0;font-weight:400}h1{font-size:28px;letter-spacing:-.6px}h2{font-size:20px;margin:24px 0 8px}button{font:inherit;cursor:pointer;border:1px solid #8884;border-radius:999px;padding:7px 15px;color:inherit;background:#ffffff18}button[aria-pressed=true]{background:#006fe6;color:white;border-color:#006fe6}button:focus-visible,summary:focus-visible{outline:2px solid #006fe6;outline-offset:3px}header{display:flex;align-items:center;justify-content:space-between;gap:20px}header p,.muted{color:#66666c}.dark header p,.dark .muted{color:#a4a4ac}.study{max-width:1320px;margin:auto;padding:32px}.toolbar{display:flex;flex-wrap:wrap;gap:8px;margin:20px 0}.family-description{max-width:900px;margin-bottom:14px;color:#66666c}.dark .family-description{color:#a4a4ac}.cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}.card{border:1px solid #7773;border-radius:18px;padding:16px;background:#ffffff20;min-width:0;overflow:hidden}.dark .card{background:#ffffff04}.card-title{display:flex;align-items:baseline;gap:8px;margin-bottom:12px;white-space:nowrap}.code{font-variant-numeric:tabular-nums;color:#006fe6;font-weight:500}.dark .code{color:#64a4ff}.card h3{font-size:14px;overflow:hidden;text-overflow:ellipsis}.samples{display:flex;align-items:center;gap:18px}.app-icon{width:84px;height:84px;border-radius:22%;background:#006fe6;color:#fff;display:flex;align-items:center;justify-content:center;flex:none}.app-icon svg{width:77%;height:auto;display:block}.wordmark{font:500 22px Comfortaa,system-ui,sans-serif;letter-spacing:-.65px;display:flex;align-items:center;gap:6px;margin-bottom:12px}.wordmark svg{width:32px;height:24px;flex:none}.sizes{display:flex;align-items:center;gap:12px;height:25px}.size{display:flex;align-items:center;gap:4px}.size svg{display:block;width:var(--size);height:var(--size)}.size small{font-size:14px;color:#77777f}.dark .size small{color:#9999a0}details{margin-top:14px}summary{cursor:pointer;color:inherit}.analysis{margin-top:10px;color:#66666c;line-height:1.55}.dark .analysis{color:#a4a4ac}.analysis p+p{margin-top:7px}.family[hidden],.card[hidden]{display:none}.sheet{width:1320px;padding:24px}.sheet header{height:60px;margin-bottom:16px}.sheet .cards{gap:12px}.sheet .card{height:174px;padding:12px 14px}.sheet .card-title{margin-bottom:9px}.sheet .samples{gap:16px}.sheet .app-icon{width:82px;height:82px}.sheet .wordmark{font-size:22px}.sheet footer{font-size:14px;color:#77777f;margin-top:14px}.dark.sheet footer{color:#9999a0}.sheet.concepts .cards{grid-template-columns:repeat(5,minmax(0,1fr));gap:14px}.sheet.concepts .card{height:268px}.sheet.concepts .samples{display:flex;flex-direction:column;gap:12px}.sheet.concepts .app-icon{width:106px;height:106px}.sheet.concepts .wordmark{justify-content:center;margin:0 0 12px}.sheet.concepts .sizes{justify-content:center}.sheet .analysis{display:none}a{color:#006fe6}.dark a{color:#64a4ff}.winner{border-color:#006fe6;box-shadow:inset 0 0 0 1px #006fe6}.judgment{padding:18px;border:1px solid #7773;border-radius:18px;margin:20px 0}.judgment p+p{margin-top:10px}.judgment h2{margin:0 0 8px}.recommendation-card{max-width:420px;margin:16px 0}.judgment details p{margin:12px 0}.recommendation-card .card{border-color:#006fe6}@media(max-width:800px){.cards{grid-template-columns:1fr}.study{padding:20px}header{align-items:start}h1{font-size:24px}}'''
(ROOT/'study.css').write_text(css)
def svg(item):
    return (ROOT/item['file']).read_text().strip()
def card(item,details=False):
    id=html.escape(item['id']);name=html.escape(item['name']);drawing=svg(item)
    sizes=''.join(f'<span class="size" style="--size:{s}px">{drawing}<small>{s}</small></span>'for s in [24,20,16])
    rationale=html.escape(item.get('rationale',item.get('logic','')));tradeoff=html.escape(item.get('tradeoff',item.get('caution','')))
    detail=f'<details><summary>Analysis and SVG</summary><div class="analysis"><p>{rationale}</p><p>{tradeoff}</p><p><a href="{html.escape(item["file"])}" download>Download {id}.svg</a></p></div></details>'if details else ''
    return f'<article class="card" data-id="{id}"><div class="card-title"><span class="code">{id}</span><h3>{name}</h3></div><div class="samples"><div class="app-icon">{drawing}</div><div><div class="wordmark">{drawing}<span>eyesight</span></div><div class="sizes">{sizes}</div></div></div>{detail}</article>'
def document(title,body,classes='',script=''):
    return f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title><link rel="stylesheet" href="study.css"></head><body class="{classes}">{body}{script}</body></html>'
header='<header><div><h1>Eyesight logo study</h1><p>15 concepts. Two refinements each. One eye narrative.</p></div><button id="theme" type="button">Change theme</button></header>'
sections=[]
for i,b in enumerate(base):
    items=[b]+sorted([r for r in refinements if r['parent']==b['id']],key=lambda x:x['id'])
    sections.append(f'<section class="family" data-group="{i//5}" id="family-{b["id"]}"><h2>{b["id"]} {html.escape(b["name"])}</h2><p class="family-description">{html.escape(b["logic"])}</p><div class="cards">'+''.join(card(item,True)for item in items)+'</div></section>')
reviews=sorted((ROOT/'reviews').glob('judge-*.json'))
judgment='<section id="judges" class="judgment"><h2>Independent visual review</h2><p>Four Luna 6 Max judges will inspect the rendered sheets after all refinements are complete.</p></section>'
if reviews:
    entries=[json.loads(p.read_text())for p in reviews]
    selection=json.loads((ROOT/'selection.json').read_text())
    best=next(i for i in all_items if i['id']==selection['winner'])
    judgment='<section id="judges" class="judgment"><h2>Recommended: '+best['id']+' '+html.escape(best['name'])+'</h2><p>Top three with every judge. 12b received two first place votes and is the closest alternative.</p><div class="recommendation-card">'+card(best)+'</div><p><a href="recommendation.html">View the recommendation</a> / <a href="concepts-light.html">View all 15 initial concepts</a> / <a href="selection.json">Complete rankings</a></p><details><summary>Read four independent judgments</summary>'+''.join(f'<p><strong>{html.escape(e["judge"])} selected {html.escape(e["winner"])}</strong>. {html.escape(e["summary"])}</p>'for e in entries)+'</details></section>'
script='''<script>document.getElementById('theme').onclick=()=>document.body.classList.toggle('dark');document.querySelectorAll('[data-filter]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-filter]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));document.querySelectorAll('.family').forEach(f=>f.hidden=b.dataset.filter!=='all'&&f.dataset.group!==b.dataset.filter)});document.querySelector('[data-filter="0"]').click();</script>'''
(ROOT/'index.html').write_text(document('Eyesight logo study','<main class="study">'+header+'<nav class="toolbar" aria-label="Concept families">'+''.join(f'<button type="button" data-filter="{g}" aria-pressed="false">{label}</button>'for g,label in [('0','01 to 05'),('1','06 to 10'),('2','11 to 15'),('all','All 45')])+'</nav>'+judgment+''.join(sections)+'</main>',script=script))
jobs=[]
for dark in [False,True]:
    theme='dark'if dark else'light'
    body='<header><h1>Eyesight: the 15 concepts</h1><p>App mark, Comfortaa lockup, 24 / 20 / 16 px</p></header><div class="cards">'+''.join(card(x)for x in base)+'</div><footer>Original concepts. Fixed blue field for comparison. Internal geometry carries the variation.</footer>'
    name=f'concepts-{theme}';(ROOT/f'{name}.html').write_text(document(name,body,f'sheet concepts {theme}'))
    jobs.append({'file':f'{name}.html','output':f'renders/{name}.png','width':1320,'height':1000})
    if len(refinements)==30:
        for group in range(3):
            items=[]
            for b in base[group*5:group*5+5]:items.extend([b]+sorted([r for r in refinements if r['parent']==b['id']],key=lambda x:x['id']))
            body=f'<header><h1>Eyesight: families {group*5+1:02} to {group*5+5:02}</h1><p>Original, refinement a, refinement b</p></header><div class="cards">'+''.join(card(x)for x in items)+'</div><footer>Actual SVG rendering. Native size samples are 24, 20 and 16 CSS pixels. The blue icon field stays constant.</footer>'
            name=f'families-{group+1}-{theme}';(ROOT/f'{name}.html').write_text(document(name,body,f'sheet {theme}'))
            jobs.append({'file':f'{name}.html','output':f'renders/{name}.png','width':1320,'height':1100})
(ROOT/'render-jobs.json').write_text(json.dumps(jobs,indent=2)+'\n')
(ROOT/'all-logos.json').write_text(json.dumps(all_items,indent=2)+'\n')
print(f'{len(base)} concepts, {len(refinements)} refinements, {len(jobs)} contact sheets')
