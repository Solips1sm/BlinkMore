"""Author the fifteen initial Eyesight concepts and their comparison metadata."""
from pathlib import Path
import json, math
ROOT = Path(__file__).resolve().parent

def ring(cx=80, cy=50, radius=16, dot=2.7, count=8):
    return '<g fill="currentColor" stroke="none">'+''.join(f'<circle cx="{cx+radius*math.cos(i*math.tau/count):.3f}" cy="{cy+radius*math.sin(i*math.tau/count):.3f}" r="{dot}"/>' for i in range(count))+'</g>'
def pupil(cx=80, cy=50, radius=3.5):
    return f'<circle cx="{cx}" cy="{cy}" r="{radius}" fill="currentColor" stroke="none"/>'
def path(d, extra=''):
    return f'<path d="{d}" {extra}/>'
al = 'M10 50C40 7 120 7 150 50C120 93 40 93 10 50Z'
items = [
('01','Soft almond','A calm, continuous almond with softened joins. The original eight dot iris remains the clearest link to the company.',path(al)+ring()+pupil(),'The closest evolution of the supplied mark. Fine dots need a small size check.'),
('02','Pill lens','A capsule turns the familiar button pill into an eye. Straight upper and lower spans make the mark compact and steady.','<rect x="14" y="21" width="132" height="58" rx="29"/>'+ring()+pupil(),'Strong family resemblance to the controls. Can read as a switch without the iris.'),
('03','Soft rectangle','A continuous rounded enclosure gives the eye a device like frame while retaining a living iris.',path('M15 50C15 25 29 17 53 17H107C131 17 145 25 145 50C145 75 131 83 107 83H53C29 83 15 75 15 50Z')+ring()+pupil(),'More architectural than organic. Avoid letting the outline resemble a camera housing.'),
('04','Open lids','Two separate arcs leave the corners open, suggesting a relaxed blink rather than an enclosing shield.',path('M12 46C44 10 116 10 148 46M20 61C52 87 108 87 140 61')+ring()+pupil(),'Airy and responsive. Open corners may weaken the silhouette at small sizes.'),
('05','Sculpted lens','A heavier upper lid and a quiet lower curve create a filled, sculptural eye with a clear aperture.',path('M9 50C41 2 119 2 151 50C122 19 38 19 9 50Z','fill="currentColor" stroke="none"')+path('M9 50C42 92 118 92 151 50')+ring(radius=14,dot=2.5)+pupil(),'A stronger app icon shape. The weighted upper lid needs balance beside Comfortaa.'),
('06','Ellipse orbit','An elliptical eye emphasizes continuous observation and a generous aperture without sharp corners.','<ellipse cx="80" cy="50" rx="65" ry="31"/>'+ring()+pupil(),'Soft and simple, with less explicit eye character than the almond.'),
('07','Lens brackets','Two curved brackets frame the iris. The missing top and bottom strokes make the eye feel open and light.',path('M49 19C26 23 17 38 12 50C17 62 26 77 49 81M111 19C134 23 143 38 148 50C143 62 134 77 111 81')+ring()+pupil(),'Distinct and spacious. Brackets can imply scanning rather than comfort.'),
('08','Resting blink','A shallow eye and low iris describe a relaxed eyelid with less vertical occupation.',path('M10 52C43 20 117 20 150 52C117 78 43 78 10 52Z')+ring(cy=50,radius=11,dot=2.5)+pupil(),'Efficient in a menu bar. The compressed eye can look sleepy.'),
('09','Paired gaze','Two separate eyes distribute the company’s eight circles equally across both sides, making bilateral movement part of the identity.',path('M8 50C24 25 56 25 72 50C56 75 24 75 8 50ZM88 50C104 25 136 25 152 50C136 75 104 75 88 50Z')+ring(cx=40,radius=9,dot=2.3,count=4)+ring(cx=120,radius=9,dot=2.3,count=4),'Directly expresses two eyes. Both small irises compete for limited menu bar pixels.'),
('10','Living seed','An asymmetric upper lid suggests movement while the iris holds a stable central anchor.',path('M10 53C40 2 116 19 150 48C120 93 47 86 10 53Z')+ring()+pupil(),'Memorable organic tension. It must remain neutral rather than suggest unequal eye health.'),
('11','Round aperture','A circular outer frame contains a simple eye cut and the eight circle iris, joining observation with a focus dial.','<circle cx="80" cy="50" r="39"/>'+path('M42 50C61 21 99 21 118 50C99 79 61 79 42 50Z')+ring(radius=12,dot=2.3)+pupil(),'Robust circular icon, with a risk of unnecessary nested boundaries.'),
('12','Petal iris','Eight rounded radial strokes reinterpret the company’s circles as a soft iris inside the eye.',path(al)+''.join(f'<path d="M{80+12*math.cos(i*math.tau/8):.3f} {50+12*math.sin(i*math.tau/8):.3f}L{80+18*math.cos(i*math.tau/8):.3f} {50+18*math.sin(i*math.tau/8):.3f}" stroke-width="5"/>' for i in range(8))+pupil(),'More legible strokes at small sizes. It can resemble a loading spinner if animated continuously.'),
('13','Forward gaze','The iris moves gently to one side inside a generous almond, suggesting attention shifting beyond the screen.',path(al)+ring(cx=91,radius=15,dot=2.6)+pupil(cx=91),'A clear eye with directional character. The resting logo should not appear to watch a particular person.'),
('14','Ribbon fold','A pair of offset lid ribbons shares rounded endings with the pill controls. The iris sits in their open overlap.',path('M12 52C42 9 113 10 145 41M15 59C48 91 120 85 148 47','stroke-width="7"')+ring(radius=13,dot=2.5)+pupil(),'Dynamic without arrows. Heavy terminals can crowd the iris.'),
('15','Constellation eye','Eight dots form the eye boundary itself, letting the company motif become the whole silhouette. A pupil makes the eye reading explicit.','<g fill="currentColor" stroke="none">'+''.join(f'<circle cx="{x}" cy="{y}" r="5"/>' for x,y in [(12,50),(38,30),(80,23),(122,30),(148,50),(122,70),(80,77),(38,70)])+'</g>'+pupil(radius=9),'The strongest departure from a conventional eye icon. Sparse dots need careful spacing at 16 pixels.')
]
manifest=[]
for id,name,logic,body,caution in items:
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 100" width="160" height="100" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">{body}</svg>\n'
    (ROOT/'concepts'/f'{id}.svg').write_text(svg)
    manifest.append({'id':id,'name':name,'logic':logic,'caution':caution,'file':f'concepts/{id}.svg'})
assert len(manifest)==15 and len({x['file'] for x in manifest})==15
(ROOT/'concepts.json').write_text(json.dumps(manifest,indent=2)+'\n')
