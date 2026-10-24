"""Validate the frozen visual review and select the equal weight mean rank winner."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parent
items=json.loads((ROOT/'all-logos.json').read_text()); ids={i['id']for i in items}
reviews=[json.loads(p.read_text())for p in sorted((ROOT/'reviews').glob('judge-*.json'))]
assert len(reviews)==4
snapshot=json.loads((ROOT/'review-snapshot.json').read_text())
for item in items:assert hashlib.sha256((ROOT/item['file']).read_bytes()).hexdigest()==snapshot['logos'][item['id']]
for name,digest in snapshot['screenshots'].items():assert hashlib.sha256((ROOT/'renders'/name).read_bytes()).hexdigest()==digest
for judge in reviews:
    assert len(judge['ranking'])==45 and set(judge['ranking'])==ids
    assert judge['winner']==judge['ranking'][0]
    assert len(judge['inspectedImages'])==6 and judge['model']=='gpt-6-luna' and judge['reasoningEffort']=='max'
rankings=[]
for item in items:
    ranks=[j['ranking'].index(item['id'])+1 for j in reviews]
    rankings.append({'id':item['id'],'name':item['name'],'ranks':ranks,'meanRank':sum(ranks)/4,'firstChoices':sum(j['winner']==item['id']for j in reviews)})
rankings.sort(key=lambda x:(x['meanRank'],-x['firstChoices'],x['id']))
selection={'method':'Equal weight mean rank across all four complete 45 candidate rankings. Lower is better. First choice votes break a tied mean, then the ID.','winner':rankings[0]['id'],'rankings':rankings,'individualWinners':{j['judge']:j['winner']for j in reviews},'limitation':'These are four subjective visual reviews of static WebKit screenshots. No human preference study or physical menu bar test is included.'}
(ROOT/'selection.json').write_text(json.dumps(selection,indent=2)+'\n')
print('Recommended:',selection['winner'],rankings[0]['name'])
