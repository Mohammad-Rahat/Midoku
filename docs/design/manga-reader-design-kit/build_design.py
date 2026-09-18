from pathlib import Path
from html import escape
import json, zipfile

ROOT = Path(__file__).parent
W, H = 393, 852
C = {'bg':'#FAFAF7','surface':'#FFFFFF','ink':'#202D26','muted':'#606D63','line':'#E7EAE4','green':'#376A50','pale':'#E9F0E9','soft':'#F0F2ED','orange':'#B66B3E'}
SCREENS = {}
META = []

def rect(x,y,w,h,fill=None,r=0,stroke=None,sw=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill or C["surface"]}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>'
def txt(x,y,s,size=14,color=None,weight=400,anchor='start',extra=''):
    return f'<text x="{x}" y="{y}" font-family="Arial, Helvetica, sans-serif" font-size="{size}" font-weight="{weight}" fill="{color or C["ink"]}" text-anchor="{anchor}" {extra}>{escape(str(s))}</text>'
def lines(x,y,ss,size=14,color=None,leading=21,weight=400):
    return ''.join(txt(x,y+i*leading,t,size,color,weight) for i,t in enumerate(ss))
def link(body,target,label=''):
    return f'<a href="#{target}" data-target="{target}" aria-label="{escape(label or target)}">{body}</a>'
def hit(x,y,w,h,target):
    return link(rect(x,y,w,h,'transparent'),target)
ICONS={
'home':'M3 10 12 3l9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z',
'library':'M4 4h4v16H4z M11 4h4v16h-4z M18 4l3 15',
'browse':'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18 M16 8l-3 5-5 3 3-5Z',
'history':'M3 10a9 9 0 1 1 1 7 M3 4v6h6 M12 7v5l3 2',
'settings':'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1Z',
'search':'M10.5 3a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15 M16 16l5 5',
'plus':'M12 5v14 M5 12h14',
'chevron':'m9 5 7 7-7 7',
'back':'m15 5-7 7 7 7',
'down':'m5 9 7 7 7-7',
'check':'m5 12 4 4L19 6',
'download':'M12 3v12 m-5-5 5 5 5-5 M4 17v4h16v-4',
'copy':'M8 8h12v13H8z M16 8V3H3v13h5',
'pin':'m8 3 8 0-1 6 4 5H5l4-5Z M12 14v7',
'sliders':'M4 6h6 M15 6h5 M4 18h11 M19 18h1 M10 3v6 M15 15v6 M4 12h1 M9 12h11 M5 9v6',
'edit':'m4 16 12-12 4 4L8 20H4Z M14 6l4 4',
'lock':'M6 10h12v11H6z M8 10V7a4 4 0 0 1 8 0v3 M12 14v3',
'sun':'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v2 M12 20v2 M2 12h2 M20 12h2 M5 5l1 1 M18 18l1 1 M5 19l1-1 M18 6l1-1',
'folder':'M3 6h7l2 3h9v11H3Z',
'cloud':'M7 18a5 5 0 1 1 0-10 6 6 0 0 1 11-2 6 6 0 0 1 0 12Z',
'grid':'M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z',
'close':'m6 6 12 12 M18 6 6 18',
'play':'m8 4 12 8-12 8Z',
'book':'M12 5C8 3 5 3 2 4v15c3-1 6-1 10 1 4-2 7-2 10-1V4c-3-1-6-1-10 1Z M12 5v15',
'refresh':'M20 8a8 8 0 0 0-14-3L3 8 M3 3v5h5 M4 16a8 8 0 0 0 14 3l3-3 M21 21v-5h-5',
'dots':'M5 12h.01 M12 12h.01 M19 12h.01',
'grip':'M7 7h.01 M17 7h.01 M7 12h.01 M17 12h.01 M7 17h.01 M17 17h.01',
'trash':'M3 6h18 M9 6V3h6v3 M5 6l1 15h12l1-15 M10 10v7 M14 10v7',
'arrow':'M4 12h16 m-6-6 6 6-6 6',
'star':'m12 3 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z',
}
def icon(name,x,y,size=22,color=None,sw=1.7):
    return f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color or C["ink"]}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"><path d="{ICONS[name]}"/></svg>'
def circle(x,y,r,fill): return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"/>'
def status(dark=False):
    co='#F7F9F5' if dark else C['ink']
    return txt(27,31,'9:41',14,co,600)+''.join(rect(290+i*5,28-(i+1)*2.5,3,(i+1)*2.5,co,1) for i in range(4))+f'<path d="M318 22q8-7 16 0m-13 3q5-4 10 0m-7 3q2-2 4 0" fill="none" stroke="{co}" stroke-width="1.7" stroke-linecap="round"/>'+rect(342,18,23,12,'none',3,co)+rect(345,21,16,6,co,1)+rect(367,22,2,4,co,1)
def nav(active):
    s=rect(0,763,W,89,'#FFFFFF')+rect(0,763,W,1,C['line'])
    for i,(name,ico) in enumerate([('Home','home'),('Library','library'),('Browse','browse'),('History','history'),('Settings','settings')]):
        x=8+i*76; c=C['green'] if name.lower()==active else '#6C766E'
        b=icon(ico,x+24,778,23,c)+txt(x+35.5,818,name,10,c,600 if name.lower()==active else 400,'middle')
        s+=link(b+rect(x,771,72,57,'transparent'),name.lower())
    return s+rect(130,839,133,5,C['ink'],3)
def base(active=None,dark=False): return rect(0,0,W,H,'#151D18' if dark else C['bg'])+status(dark)
def homebar(dark=False): return rect(130,839,133,5,'#D6DFD7' if dark else C['ink'],3)
def heading(title,subtitle='',action='sliders',target='settings'):
    return txt(24,92,title,32,weight=700)+link(rect(325,60,44,44,C['soft'],22)+icon(action,336,71),target)+(txt(24,121,subtitle,13,C['muted']) if subtitle else '')
def backbar(title='',target='library',right='dots',righttarget='edit'):
    return link(icon('back',20,61,24),target)+txt(50,79,title,15,weight=500)+link(rect(325,50,44,44,'transparent',22)+icon(right,336,61),righttarget)
def chip(x,y,w,label,active=False,target=None):
    s=rect(x,y,w,32,C['green'] if active else C['soft'],16)+txt(x+w/2,y+21,label,12,'#FFFFFF' if active else C['muted'],600 if active else 400,'middle')
    return link(s,target) if target else s
def btn(x,y,w,label,target,kind='primary',ico=None):
    fill=C['green'] if kind=='primary' else C['pale']; co='#FFFFFF' if kind=='primary' else C['green']
    b=rect(x,y,w,48,fill,14)+txt(x+w/2+(10 if ico else 0),y+30,label,14,co,600,'middle')
    if ico:b+=icon(ico,x+24,y+14,20,co)
    return link(b,target)
def section(y,title,action='View all',target='source'):
    return txt(24,y,title,19,weight=700)+link(txt(369,y,action,12,C['green'],500,'end'),target)
def search(y,label,target='search'):
    return link(rect(24,y,345,44,C['soft'],13)+icon('search',38,y+12,20,C['muted'])+txt(70,y+28,label,14,C['muted']),target)
def badge(x,y,label,green=True):
    w=len(label)*5.7+16
    return rect(x,y,w,20,C['pale'] if green else '#F3E9DF',6)+txt(x+8,y+14,label,10,C['green'] if green else C['orange'],600)

# Original editorial cover art: intentionally abstract, no external assets.
BOOKS=[('Naruto','MASASHI KISHIMOTO','#E2A56B','#B6532C'),('Frieren','BEYOND JOURNEY’S END','#B8CDC2','#4D796F'),('Blue Period','TSUBASA YAMAGUCHI','#AFC2D7','#3E638C'),('Vagabond','TAKEHIKO INOUE','#B9B8A8','#4F594B'),('Witch Hat','KAMOME SHIRAHAMA','#CAC3DA','#746C8E'),('One Piece','EIICHIRO ODA','#D9C994','#817653')]
def cover(idx,x,y,w,h,r=9):
    title,sub,bg,fg=BOOKS[idx%len(BOOKS)]
    # Nested SVG gives artwork reliable clipping while retaining editable vectors.
    s=f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 120 174" preserveAspectRatio="xMidYMid slice">'
    s+=rect(0,0,120,174,bg,r)+circle(96,34,43,fg)+circle(83,34,36,bg)
    s+=f'<path d="M-8 142 62 61l69 106M-10 126 41 76 123 163" fill="none" stroke="{fg}" stroke-width="1" opacity=".32"/>'
    if idx%6==0:
        s+=f'<path d="m57 55 6-14 6 8 8-16 5 16 13-7-3 15 12 3-12 11-3 26H61l-7-23-9-9Z" fill="{fg}"/>'
        s+=f'<path d="M21 152q7-54 47-60 35-2 47 56Z" fill="{fg}"/><path d="M62 66h28v8H62Z" fill="{bg}"/>'
    elif idx%6==1:
        s+=f'<path d="M39 135q-13-54 10-77 16-14 32 5l12 85Z" fill="{fg}"/><ellipse cx="66" cy="72" rx="15" ry="19" fill="{bg}"/><path d="m48 80-21-9 22 19m32-10 22-9-22 19" fill="{bg}"/>'
    elif idx%6==2:
        s+=f'<path d="m13 128 87-60M7 113l83-58M24 149l86-59" stroke="{fg}" stroke-width="21"/><circle cx="55" cy="78" r="19" fill="{bg}"/>'
    elif idx%6==3:
        s+=f'<path d="m48 88 9-32 18-4 13 20-15 31 31 50H25Z" fill="{fg}"/><path d="m7 138 109-54" stroke="{bg}" stroke-width="3"/>'
    elif idx%6==4:
        s+=f'<path d="m27 83 44-47 11 50 24 13-94-1Z" fill="{fg}"/><path d="m43 106-21 49h84l-29-52Z" fill="{fg}"/>'
    else:
        s+=f'<path d="m22 109 79-2-14 28H40Z" fill="{fg}"/><path d="M64 48v62M60 50 29 98h31m8-45 26 40H68" stroke="{fg}" stroke-width="3" fill="none"/>'
    s+=rect(0,0,120,42,bg)+txt(10,20,title.upper(),12,'#263229',700)+txt(10,31,sub[:22],4.7,'#384336',500)
    s+=rect(0,157,120,17,bg)+txt(10,168,'THE COLLECTION',5.5,'#384336',500)+txt(109,168,f'{idx+1:02d}',7,'#384336',600,'end')+'</svg>'
    return s
def bookcard(i,x,y,w=105,target='detail',subtitle=''):
    return link(cover(i,x,y,w,w*1.43)+txt(x,y+w*1.43+20,BOOKS[i][0],13,weight=600)+txt(x,y+w*1.43+37,subtitle or 'MangaDex',10,C['muted']),target)
def row(y,title,subtitle,ico,target,trail=''):
    return link(icon(ico,36,y+17,21,C['green'])+txt(73,y+28,title,14,weight=500)+(txt(73,y+48,subtitle,11,C['muted']) if subtitle else '')+(txt(337,y+29,trail,12,C['muted'],anchor='end') if trail else '')+icon('chevron',342,y+20,16,C['muted']),target)
def chapter(y,num,title,source='MangaDex',read=False,copied=False,download=False):
    co=C['muted'] if read else C['ink']
    s=cover(0,24,y+9,44,56,5)+txt(82,y+25,f'Chapter {num}',14,co,600)+txt(82,y+43,title,12,C['muted'])
    s+=txt(82,y+61,source,10,C['green'] if copied else C['muted'],600 if copied else 400)
    s+=icon('check' if read else 'download' if download else 'dots',340,y+26,18,C['green'] if read else C['muted'])
    if copied:s+=badge(158,y+47,'Added source')
    s+=rect(82,y+76,287,1,C['line'])
    return link(s,'reader' if read or copied else 'chapter-menu')
def screen(key,title,desc,s,active=None,dark=False):
    s+=nav(active) if active else homebar(dark)
    SCREENS[key]=f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="{escape(title)}"><title>{escape(title)}</title>{s}</svg>'
    META.append({'id':key,'title':title,'description':desc})

# Five primary destinations.
s=base()+heading('Home','A little discovery. A little escape.','sliders','home-sections')
s+=section(174,'Pick up where you left off','', 'reader')
s+=link(rect(24,193,345,153,C['pale'],18)+cover(0,36,205,86,128)+txt(139,230,'NARUTO',11,C['green'],600)+txt(139,255,'The story continues.',17,weight=600)+txt(139,277,'Chapter 20 · 12 of 19 pages',11,C['muted'])+rect(139,293,198,3,'#CDDACD',2)+rect(139,293,122,3,C['green'],2)+txt(139,322,'Continue reading',12,C['green'],600)+icon('arrow',320,307,19,C['green']),'reader')
s+=section(386,'Popular on MangaDex')+txt(24,408,'PINNED COLLECTION',9,C['muted'],600,extra='letter-spacing="1.1"')
for i,x in zip([1,2,3],[24,147,270]):s+=bookcard(i,x,426,99)
s+=section(653,'Latest from MangaSee')
for i,x in zip([4,5,0],[24,147,270]):s+=link(cover(i,x,674,99,144),'detail')
screen('home','Home','Pinned discovery with a quiet continue-reading card.',s,'home')

s=base()+heading('Library','24 stories, all yours.','plus','browse')+search(145,'Search your library')
for x,w,l,a in [(24,46,'All',1),(78,81,'Reading',0),(167,78,'Planned',0),(253,105,'Completed',0)]:s+=chip(x,208,w,l,a,'categories' if l!='All' else 'library')
s+=txt(24,271,'Recently read',12,C['muted'])+icon('down',104,259,15,C['muted'])+link(icon('sliders',345,253,21,C['muted']),'categories')
for i,(x,y) in enumerate([(24,292),(147,292),(270,292),(24,504),(147,504),(270,504)]):
    s+=bookcard(i,x,y,99,subtitle=['12 unread','3 unread','Up to date','28 unread','8 unread','42 unread'][i])
    if i in [0,1,4]:s+=badge(x+8,y+115,['12','3','','','8'][i])
screen('library','Library','Personal collection with categories and unread counts.',s,'library')

s=base()+heading('Browse','Find your next favorite.','plus','extensions')+search(145,'Search all extensions')
s+=section(229,'Your extensions','Manage','extensions')
for k,(name,sub,co,abbr) in enumerate([('MangaDex','English · All genres','#EAE3D5','M'),('MangaSee','English · Manga & comics','#DBE9DE','MS'),('ComicK','English · Manga & webtoons','#E3E5F0','C')]):
    y=250+k*92
    s+=link(rect(24,y,345,78,C['surface'],16,C['line'])+rect(38,y+15,48,48,co,13)+txt(62,y+46,abbr,17,C['ink'],700,'middle')+txt(102,y+31,name,16,weight=600)+txt(102,y+53,sub,11,C['muted'])+icon('chevron',340,y+28,19,C['muted']),'source-mangasee' if name=='MangaSee' else 'source')
s+=rect(24,556,345,113,C['pale'],16)+icon('pin',42,576,22,C['green'])+txt(78,593,'Make discovery yours',14,C['green'],600)+lines(42,622,['Hold any extension tab to pin it to Home.','Your favorite feeds, one tap away.'],12,C['muted'],20)
screen('browse','Browse','Global search and a concise extension directory.',s,'browse')

s=base()+heading('History','Your last 100 chapters.','dots','settings')+txt(24,169,'TODAY',10,C['muted'],600,extra='letter-spacing="1"')
for i,(bk,title,sub,src,time,prog) in enumerate([(0,'Naruto','Chapter 20 · A New Chapter','MangaDex','12 min ago',.63),(1,'Frieren','Chapter 44 · The Journey','MangaDex','1 hour ago',.3),(2,'Blue Period','Chapter 12 · Colors','MangaSee','3 hours ago',1)]):
    y=187+i*122
    s+=link(cover(bk,24,y,57,82)+txt(97,y+19,title,16,weight=600)+txt(97,y+41,sub,12,C['muted'])+txt(97,y+61,src,10,C['muted'])+txt(369,y+61,time,10,C['muted'],anchor='end')+rect(97,y+75,272,3,C['line'],2)+rect(97,y+75,272*prog,3,C['green'],2),'reader')
s+=txt(24,579,'YESTERDAY',10,C['muted'],600,extra='letter-spacing="1"')
s+=link(cover(3,24,600,57,82)+txt(97,621,'Vagabond',16,weight=600)+txt(97,645,'Chapter 38 · Resolve',12,C['muted'])+txt(97,671,'MangaDex · Finished',11,C['muted'])+icon('check',343,625,21,C['green']),'reader')
screen('history','History','Resume recent chapters without clutter.',s,'history')

s=base()+heading('Settings','Make room for your way of reading.','sun','settings')+txt(24,169,'PERSONALIZE',10,C['muted'],600,extra='letter-spacing="1"')+rect(24,185,345,264,C['surface'],16,C['line'])
for y,ti,sub,ic,ta,tr in [(185,'Appearance','','sun','settings','System'),(249,'Home sections','','pin','home-sections','3'),(313,'Library categories','','folder','categories','4'),(377,'Reader preferences','','book','reader-settings','')]:
    s+=row(y,ti,sub,ic,ta,tr)
    if y<377:s+=rect(73,y+63,276,1,C['line'])
s+=txt(24,482,'YOUR APP',10,C['muted'],600,extra='letter-spacing="1"')+rect(24,499,345,200,C['surface'],16,C['line'])
for y,ti,ic,ta,tr in [(499,'App lock','lock','app-lock','Off'),(564,'Extensions','grid','extensions','3'),(629,'Downloads & storage','download','downloads','1.2 GB')]:
    s+=row(y,ti,'',ic,ta,tr)
    if y<629:s+=rect(73,y+64,276,1,C['line'])
s+=link(txt(196.5,731,'Backup & restore',12,C['green'],500,'middle'),'backup')
screen('settings','Settings','Grouped native controls with generous tap targets.',s,'settings')

# Reading and curation flows.
s=base()+backbar('Library',right='edit',righttarget='edit')
s+=cover(0,24,110,105,153)+txt(150,132,'YOUR COLLECTION',9,C['green'],600,extra='letter-spacing="1"')+txt(150,167,'Naruto',29,weight=700)+txt(150,192,'Masashi Kishimoto',12,C['muted'])+badge(150,209,'Completed')+txt(150,249,'2 sources · 700 chapters',11,C['muted'])
s+=lines(24,294,['A young ninja with a sealed spirit dreams of','earning his village’s respect and becoming Hokage.'],13,C['muted'],21)
s+=btn(24,338,345,'Continue · Chapter 20','reader',ico='play')
s+=chip(24,402,85,'Reading',True,'categories')+chip(117,402,92,'Adventure')+link(txt(369,423,'Edit details',12,C['green'],500,'end'),'edit')
s+=rect(24,454,345,1,C['line'])+section(490,'Chapters','Paste 1','paste')+txt(24,514,'Ascending · All sources',11,C['muted'])+link(icon('sliders',345,499,20,C['muted']),'chapter-menu')
s+=chapter(529,19,'The Symbol of Courage',read=True)+chapter(606,20,'A New Chapter',download=True)+chapter(683,21,'The Forest of Death','MangaSee',copied=True)
screen('detail','Manga details','Editable metadata above the combined chapter sequence.',s,'library')

s=base()+backbar('Browse',target='browse',right='dots',righttarget='extensions')+rect(24,111,54,54,'#EAE3D5',15)+txt(51,146,'M',21,weight=700,anchor='middle')+txt(95,134,'MangaDex',26,weight=700)+txt(96,158,'English · 28,400 titles',12,C['muted'])+search(186,'Search MangaDex','search')
for x,w,la,ac in [(24,70,'Latest',False),(102,83,'Popular',True),(193,92,'Trending',False)]:s+=chip(x,250,w,la,ac,'pin-menu')
s+=link(icon('sliders',344,256,20,C['muted']),'search')+txt(24,315,'Popular this week',13,C['muted'])
for i,(x,y) in enumerate([(24,338),(147,338),(270,338),(24,550),(147,550),(270,550)]):s+=bookcard([1,0,2,3,4,5][i],x,y,99,target='source-detail',subtitle=['Adventure','Action','Drama','Historical','Fantasy','Adventure'][i])
screen('source','Extension','Source-defined discovery tabs with pinning.',s,'browse')

s=base()+backbar('MangaSee',target='browse',right='search',righttarget='search')+cover(0,24,110,99,144)+txt(145,139,'Naruto',28,weight=700)+txt(145,166,'Masashi Kishimoto',12,C['muted'])+badge(145,184,'MangaSee')+txt(145,234,'Complete · English',12,C['muted'])+btn(24,282,345,'Add to your library','detail',kind='secondary',ico='plus')
s+=section(379,'Chapters','Select','chapter-menu')+txt(24,405,'700 chapters · Ascending',12,C['muted'])
for y,n,title in [(426,19,'The Symbol of Courage'),(504,20,'A New Chapter'),(582,21,'The Forest of Death'),(660,22,'A Worthy Opponent')]:s+=chapter(y,n,title,'MangaSee')
screen('source-detail','Source manga','Browse chapters from another extension before copying.',s,'browse')

s=base()+link(txt(24,79,'Cancel',15,C['green']),'detail')+txt(196.5,79,'Edit manga',17,weight=600,anchor='middle')+link(txt(369,79,'Save',15,C['green'],600,'end'),'detail')
s+=cover(0,153,108,87,126)+link(rect(142,246,110,30,C['pale'],15)+txt(197,266,'Change cover',11,C['green'],600,'middle'),'cover-picker')
for y,label,value in [(309,'TITLE','Naruto'),(405,'AUTHOR','Masashi Kishimoto'),(501,'DESCRIPTION','A young ninja dreams of becoming Hokage.')]:
    s+=txt(24,y,label,10,C['muted'],600,extra='letter-spacing="1"')+rect(24,y+14,345,54,C['surface'],12,C['line'])+txt(39,y+46,value,13)
s+=txt(24,599,'READING STATUS',10,C['muted'],600,extra='letter-spacing="1"')+rect(24,614,345,52,C['surface'],12,C['line'])+txt(39,646,'Reading',14)+icon('down',337,630,18,C['muted'])
s+=rect(24,689,345,73,C['pale'],14)+icon('lock',40,711,19,C['green'])+lines(73,715,['Your edits stay yours.','Refreshing sources won’t overwrite them.'],12,C['green'],21)
screen('edit','Edit manga','Personal fields and a replaceable cover.',s)

s=base()+backbar('Naruto',target='detail',right='close',righttarget='detail')+txt(24,132,'Paste chapters',29,weight=700)+lines(24,161,['One chapter, right where it belongs.'],13,C['muted'])
s+=txt(24,211,'FROM YOUR CLIPBOARD',10,C['muted'],600,extra='letter-spacing="1"')+rect(24,228,345,109,C['surface'],16,C['line'])+cover(0,39,241,55,81)+txt(109,259,'Chapter 21',17,weight=600)+txt(109,284,'The Forest of Death',12,C['muted'])+badge(109,299,'MangaSee')+icon('check',335,266,21,C['green'])
s+=txt(24,384,'YOUR READING ORDER',10,C['muted'],600,extra='letter-spacing="1"')
s+=rect(24,402,345,226,C['surface'],16,C['line'])
for y,num,sub,active in [(428,'20','MangaDex',False),(500,'21','MangaSee · Adding',True),(571,'22','MangaDex',False)]:
    if active:s+=rect(36,y-17,321,66,C['pale'],10)
    s+=circle(61,y+10,18,C['green'] if active else C['soft'])+txt(61,y+15,num,12,'#FFFFFF' if active else C['muted'],600,'middle')+txt(93,y+7,'Chapter '+num,14,weight=600)+txt(93,y+27,sub,11,C['green'] if active else C['muted'])
    if active:s+=icon('plus',326,y,20,C['green'])
s+=lines(24,663,['The chapter keeps its original source.','Your reading order and progress stay intact.'],12,C['muted'],21)+btn(24,742,345,'Add 1 chapter','paste-success',ico='plus')
screen('paste','Paste review','Show origin and insertion point before adding.',s)

s=base(dark=True)+link(icon('back',22,62,22,'#E8EDE8'),'detail')+txt(196.5,76,'Naruto',15,'#F6F8F4',600,'middle')+txt(196.5,98,'Chapter 20 · MangaDex',10,'#9CAA9D',anchor='middle')+link(icon('dots',344,63,23,'#E8EDE8'),'reader-settings')
# A purpose-made vector sample page, not copied manga artwork.
s+=rect(13,123,367,556,'#F6F4EE',2)
s+=rect(24,137,345,206,'#D9DCD2',0,'#29332D',1.5)
s+='<g stroke="#6F7A6F" stroke-width="1" fill="none">'+''.join(f'<path d="M{30+i*18} 137 90 343"/>' for i in range(19))+'</g>'
s+='<path d="m24 289 63-88 54 60 66-104 68 118 45-65 49 70v63H24Z" fill="#879888"/><path d="m24 311 89-58 68 70 72-46 116 36v30H24Z" fill="#526A55"/>'
s+='<path d="m160 223 32-25 28 26-8 38 25 69h-96l31-74Z" fill="#273B2D"/><path d="m172 220 31 2" stroke="#E7E8DE" stroke-width="7"/>'
s+=rect(24,356,160,201,'#ECEDE5',0,'#29332D',1.5)+rect(196,356,173,201,'#BAC9B6',0,'#29332D',1.5)
s+='<path d="M34 552q3-64 33-78l1-48 24-32 28 6 17 33-9 44q29 21 44 75Z" fill="#3A4B3E"/><path d="m62 429 79 0" stroke="#CBCDBF" stroke-width="9"/>'
s+='<path d="M197 510q87-37 171-80M198 526q92-39 170-81M198 543q108-51 170-83" stroke="#ECF0E5" stroke-width="8"/>'
s+=f'<ellipse cx="289" cy="399" rx="53" ry="28" fill="#F9F9F1" stroke="#29332D"/>'+lines(289,397,['WE KEEP','GOING.'],9,'#29332D',12,700).replace('text-anchor="start"','text-anchor="middle"')
s+=rect(24,570,345,96,'#D6DBCF',0,'#29332D',1.5)+f'<path d="M27 644q83-51 170 2 73 36 172-18" stroke="#536A58" stroke-width="23" fill="none"/>'+txt(47,598,'A new chapter begins.',10,'#2D3B30',500)
s+=txt(24,721,'12',12,'#EFF4ED',600)+rect(54,714,257,3,'#3C483F',2)+rect(54,714,162,3,'#BACDBA',2)+circle(216,715.5,5,'#E0EBDE')+txt(369,721,'19',12,'#91A293',anchor='end')
s+=link(icon('back',29,765,21,'#E0EADD'),'reader')+txt(196.5,781,'Tap to hide controls',11,'#91A293',anchor='middle')+link(icon('chevron',343,765,21,'#E0EADD'),'next-chapter')
screen('reader','Reader','Quiet dark controls around a full-width sample page.',s,dark=True)

# Management screens.
s=base()+backbar('Settings',target='settings',right='plus',righttarget='browse')+txt(24,131,'Home sections',28,weight=700)+txt(24,160,'Your Home, in your order.',13,C['muted'])
for i,(title,sub,ic) in enumerate([('Continue Reading','Your library','history'),('Popular','MangaDex · English','pin'),('Latest','MangaSee · English','pin')]):
    y=203+i*107
    s+=rect(24,y,345,88,C['surface'],16,C['line'])+icon(ic,41,y+28,24,C['green'])+txt(86,y+33,title,16,weight=600)+txt(86,y+57,sub,11,C['muted'])+icon('grip',329,y+28,22,C['muted'])
s+=lines(24,564,['Drag the handles to rearrange sections.','Swipe a section to hide or remove it.'],13,C['muted'],23)+btn(24,654,345,'Discover more sections','browse',kind='secondary',ico='plus')
screen('home-sections','Home sections','Reorder, hide, and remove pinned source feeds.',s)

s=base()+backbar('Settings',target='settings',right='plus',righttarget='extension-add')+txt(24,132,'Extensions',29,weight=700)+txt(24,161,'Small connections. Endless stories.',13,C['muted'])
s+=rect(24,191,345,71,C['pale'],15)+icon('check',41,215,23,C['green'])+txt(81,220,'Everything is up to date',14,C['green'],600)+txt(81,243,'Last checked just now',11,C['muted'])
s+=txt(24,302,'INSTALLED',10,C['muted'],600,extra='letter-spacing="1"')
for i,(name,version) in enumerate([('MangaDex','1.2.0'),('MangaSee','1.0.4'),('ComicK','1.1.2')]):
    y=322+i*104
    s+=rect(24,y,345,88,C['surface'],14,C['line'])+txt(42,y+30,name,16,weight=600)+txt(42,y+55,'v'+version+' · English',11,C['muted'])+link(rect(304,y+25,47,28,C['green'],14)+circle(337,y+39,10,'#FFFFFF'),'extension-toggle')
s+=link(txt(24,670,'Check for updates',13,C['green'],600)+icon('refresh',343,653,22,C['green']),'extension-refresh')+rect(24,693,345,1,C['line'])+link(txt(24,727,'Extension repository',13)+icon('chevron',345,711,18,C['muted']),'extension-add')
screen('extensions','Extension management','Versions, enabled states, and updates.',s)

s=base()+backbar('Settings',target='settings',right='plus',righttarget='category-add')+txt(24,132,'Categories',29,weight=700)+txt(24,161,'A place for every kind of story.',13,C['muted'])
for i,(name,count) in enumerate([('Reading','8 manga'),('Planned','10 manga'),('Completed','4 manga'),('Favorites','6 manga')]):
    y=205+i*99
    s+=rect(24,y,345,81,C['surface'],15,C['line'])+icon('folder',40,y+26,23,C['green'])+txt(84,y+32,name,16,weight=600)+txt(84,y+54,count,11,C['muted'])+icon('grip',328,y+28,22,C['muted'])
s+=lines(24,646,['A manga can belong to more than one category.','Removing a category keeps your manga safe.'],12,C['muted'],22)+btn(24,718,345,'New category','category-add',kind='secondary',ico='plus')
screen('categories','Categories','Flexible organization without tying entries to one group.',s)

s=base()+backbar('Settings',target='settings',right='dots',righttarget='clear-cache')+txt(24,132,'Downloads',29,weight=700)+txt(24,161,'Your stories, even offline.',13,C['muted'])+rect(24,190,345,109,C['pale'],16)+txt(43,221,'1.2 GB',28,C['green'],700)+txt(43,244,'Downloaded chapters',12,C['muted'])+rect(43,266,307,5,'#D1DDD0',3)+rect(43,266,121,5,C['green'],3)
s+=section(344,'Download queue','Pause','download-pause')+rect(24,364,345,107,C['surface'],16,C['line'])+cover(1,39,377,48,71)+txt(104,397,'Frieren',16,weight=600)+txt(104,421,'Chapter 45 · Downloading',11,C['muted'])+rect(104,441,245,3,C['line'],2)+rect(104,441,155,3,C['green'],2)
s+=section(517,'Saved on this device','', 'library')
for y,i,sub in [(540,0,'12 chapters · 340 MB'),(633,3,'28 chapters · 860 MB')]:s+=link(cover(i,24,y,44,64)+txt(84,y+22,BOOKS[i][0],15,weight=600)+txt(84,y+45,sub,11,C['muted'])+icon('chevron',344,y+23,18,C['muted']),'detail')
s+=link(txt(24,757,'Clear temporary cache',12,C['green'])+txt(369,757,'84 MB',12,C['muted'],anchor='end'),'clear-cache')
screen('downloads','Downloads & storage','Queue progress separated from temporary cache.',s)

s=base()+backbar('Settings',target='settings',right='close',righttarget='settings')+txt(24,132,'Reader preferences',27,weight=700)+txt(24,163,'Settle into your favorite way to read.',13,C['muted'])+txt(24,210,'READING MODE',10,C['muted'],600,extra='letter-spacing="1"')
for x,label,selected in [(24,'Right to left',True),(143,'Left to right',False),(262,'Continuous',False)]:
    s+=link(rect(x,228,107,112,C['pale'] if selected else C['surface'],14,C['green'] if selected else C['line'])+icon('book' if label!='Continuous' else 'library',x+39,248,28,C['green'] if selected else C['muted'])+txt(x+53.5,318,label,11,C['green'] if selected else C['muted'],600,'middle'),'reader-mode')
s+=txt(24,384,'NAVIGATION & DISPLAY',10,C['muted'],600,extra='letter-spacing="1"')+rect(24,404,345,236,C['surface'],16,C['line'])
for y,title,ic,trail in [(404,'Tap to navigate','grid','On'),(463,'Image scaling','sliders','Fit width'),(522,'Orientation','refresh','Automatic'),(581,'Background','sun','Dark')]:
    s+=row(y,title,'',ic,'reader-setting',trail)
    if y<581:s+=rect(73,y+58,276,1,C['line'])
s+=rect(24,670,345,79,C['pale'],14)+lines(42,698,['You can choose a different reading mode','for each manga from inside the reader.'],12,C['green'],22)+btn(24,772,345,'Back to reading','reader')
screen('reader-settings','Reader preferences','Reading modes and simple per-manga overrides.',s)

s=base()+backbar('Browse',target='browse',right='close',righttarget='browse')+txt(24,132,'Search everywhere',28,weight=700)+search(155,'Naruto')+txt(24,232,'RESULTS FROM 3 EXTENSIONS',10,C['muted'],600,extra='letter-spacing="1"')
for i,(name,sub,target) in enumerate([('MangaDex','In your library','detail'),('MangaSee','700 chapters · English','source-detail'),('ComicK','700 chapters · English','source-detail')]):
    y=261+i*148
    s+=section(y,name,'View all','source')+link(cover(0,24,y+18,61,87)+txt(101,y+43,'Naruto',18,weight=600)+txt(101,y+68,'Masashi Kishimoto',12,C['muted'])+txt(101,y+91,sub,11,C['green'] if i==0 else C['muted'])+icon('chevron',344,y+51,20,C['muted']),target)
screen('search','Global search','Progressive results retain their source context.',s,'browse')

# Contextual states use complete screens so every frame imports cleanly.
def overlay(key,title,desc,basekey,body):
    original=SCREENS[basekey]
    SCREENS[key]=original
    pos=SCREENS[key].rfind('</svg>')
    SCREENS[key]=SCREENS[key][:pos]+rect(0,0,W,H,'#142318')[:-2]+' opacity=".24"/>'+body+SCREENS[key][pos:]
    META.append({'id':key,'title':title,'description':desc})

body=rect(88,294,281,178,C['surface'],16)+txt(109,324,'Popular · MangaDex',13,C['muted'],600)+rect(108,343,241,1,C['line'])+link(icon('pin',109,361,21,C['green'])+txt(144,377,'Pin to Home',15,C['green'],600)+rect(100,347,256,51,'transparent'),'pin-success')+rect(108,404,241,1,C['line'])+link(icon('close',109,422,21,C['muted'])+txt(144,438,'Cancel',14),'source')
overlay('pin-menu','Pin a source tab','Discovery pinning in two taps.','source',body)

body=rect(0,449,W,403,C['surface'],24)+rect(171,460,51,5,'#D8DDD6',3)+txt(24,503,'Chapter 21',21,weight=700)+txt(24,528,'The Forest of Death · MangaSee',12,C['muted'])+rect(24,548,345,1,C['line'])
for y,ti,ico,target in [(560,'Read chapter','book','reader'),(618,'Copy chapter','copy','copy-success'),(676,'Add to another entry','plus','paste'),(734,'Edit in your library','edit','edit')]:body+=link(icon(ico,27,y+14,22,C['green'])+txt(69,y+31,ti,15)+rect(24,y,345,54,'transparent'),target)
body+=homebar()
overlay('chapter-menu','Chapter actions','Copy a chapter without losing its source.','source-detail',body)

def state_from(key,title,desc,basekey,message,target=None):
    original=SCREENS[basekey];p=original.rfind('</svg>')
    toast=rect(24,697,345,51,C['ink'],14)+icon('check',40,712,20,'#E2EDDF')+txt(72,728,message,12,'#FFFFFF',500)
    if target:toast=link(toast,target)
    SCREENS[key]=original[:p]+toast+original[p:]; META.append({'id':key,'title':title,'description':desc})
SCREENS['source-mangasee']=SCREENS['source'].replace('MangaDex','MangaSee').replace('>M</text>','>MS</text>')
META.append({'id':'source-mangasee','title':'MangaSee','description':'A second extension for finding missing chapters.'})
SCREENS['entry-before']=SCREENS['detail'].replace(chapter(683,21,'The Forest of Death','MangaSee',copied=True),chapter(683,22,'A Worthy Opponent','MangaDex'))
META.append({'id':'entry-before','title':'Naruto · Before paste','description':'Chapter 21 is missing between Chapters 20 and 22.'})
state_from('copy-success','Chapter copied','A persistent in-app clipboard, ready to paste.','entry-before','1 chapter copied · Tap Paste 1','paste')
state_from('paste-success','Chapter added','Insertion retains the original extension label.','detail','Chapter 21 added from MangaSee','reader')
state_from('pin-success','Section pinned','The saved feed is now available on Home.','home','Popular pinned to Home','home-sections')

def output():
    for key,s in SCREENS.items():(ROOT/'screens'/f'{key}.svg').write_text(s)
    main=['home','library','browse','history','settings','detail','source','source-detail','edit','paste','reader','home-sections','extensions','categories','downloads','reader-settings','search','pin-menu','chapter-menu','paste-success']
    cols=5; gap=44; outer=64; rowgap=116; top=280
    bw=outer*2+cols*W+(cols-1)*gap; bh=top+4*(H+rowgap)+100
    b=rect(0,0,bw,bh,'#E9ECE6')+txt(64,83,'THE READER',13,C['green'],700,extra='letter-spacing="3"')+txt(64,142,'A quiet place for every story.',43,weight=600)+txt(64,181,'iOS app design · 20 screens & states · Personal collections, connected sources.',17,C['muted'])
    for i,key in enumerate(main):
        x=outer+(i%cols)*(W+gap); y=top+(i//cols)*(H+rowgap)
        m=next(m for m in META if m['id']==key)
        b+=txt(x,y-24,f'{i+1:02d}  '+m['title'],16,weight=600)
        b+=f'<svg x="{x}" y="{y}" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'+SCREENS[key].split('>',1)[1].rsplit('</svg>',1)[0]+'</svg>'
        b+=rect(x,y,W,H,'none',0,'#D1D8CF')
    b+=txt(64,bh-58,'Warm white / Forest / Ink',15,weight=600)+txt(bw-64,bh-58,'Original vector cover artwork · Draft design for review',13,C['muted'],anchor='end')
    board=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {bw} {bh}" width="{bw}" height="{bh}">{b}</svg>'
    (ROOT/'manga-reader-design-board.svg').write_text(board)
    (ROOT/'design-tokens.json').write_text(json.dumps({'colors':C,'canvas':{'width':W,'height':H},'spacing':[4,8,12,16,24,32],'radii':{'input':12,'card':16,'button':14,'pill':999},'typography':{'design':'Arial','iosImplementation':'SF Pro / system font','largeTitle':32,'title':28,'section':19,'body':14,'caption':12},'touchTargetMin':44},indent=2))
    (ROOT/'README.md').write_text('''# iOS Manga Reader — Design handoff

Minimal native iOS direction: warm white, forest accents, charcoal type, quiet separators, and editorial cover art.

## Files
- `manga-reader-design-board.svg`: 20-screen vector design board. Drag into a Figma design file to import vector layers.
- `screens/`: Individual SVG screen files for easier import and iteration.
- `manga-reader-preview.html`: Self-contained clickable preview; open in a browser. Main navigation and the pin/copy/paste reading flows are connected. Utility actions display feedback only; this is a design prototype.
- `design-tokens.json`: Color, typography, spacing, and radius references.
- `build_design.py`: Reproducible source for the supplied vectors and preview.

## Key review flows
1. Browse → MangaDex → Popular → Pin to Home.
2. Browse → MangaDex → manga → chapter action → Copy → Paste 1 → Add chapter.
3. Library → Naruto → Continue → reader preferences.
4. Settings → home sections, extensions, categories, and downloads.

## Design notes
- The five tabs are always labelled. Reader and focused editing screens hide the tab bar.
- Chapter origin appears below chapter details; mixed sources remain visible in the combined entry.
- Category membership, publication status, and reading progress are separate concepts.
- Cover and reader artwork is original abstract vector sample art, not official book covers.
- Shortened lists represent viewport samples. Long content should scroll in the implementation.
- Figma import produces vector layers; native Figma component instances, auto-layout, and prototype links were not created because the Figma editing connection was unavailable. The HTML preview supplies navigation separately.
- No live search, data storage, extension execution, or actual downloads are implemented in this design preview.
''')
    data=json.dumps(SCREENS).replace('</script','<\\/script'); meta=json.dumps(META)
    html='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Manga Reader — Design Preview</title><style>
*{box-sizing:border-box}body{margin:0;background:#e9ece6;color:#202d26;font-family:Arial,Helvetica,sans-serif}button{font:inherit;cursor:pointer} .layout{min-height:100vh;display:grid;grid-template-columns:280px 1fr}aside{padding:42px 30px;background:#f7f8f3;border-right:1px solid #dbe0d7;position:sticky;top:0;height:100vh;overflow:auto}.eyebrow{color:#376a50;font-size:10px;font-weight:700;letter-spacing:2px}h1{font-size:29px;line-height:1.2;letter-spacing:-1px;margin:19px 0 12px}p{color:#606d63;font-size:13px;line-height:1.65}.screenlist{margin-top:26px;display:grid;gap:3px}.screenlist button{text-align:left;border:0;background:none;color:#606d63;padding:10px 12px;border-radius:8px;font-size:12px}.screenlist button.active{background:#e2ecdf;color:#376a50;font-weight:600}.num{display:inline-block;width:26px;font-size:10px;opacity:.65}.stage{padding:30px 35px 38px;display:flex;align-items:center;flex-direction:column;gap:18px;min-width:0}.top{display:flex;width:min(700px,100%);align-items:center;justify-content:space-between;font-size:11px;color:#606d63}.top button{border:1px solid #cbd4c8;border-radius:30px;padding:8px 15px;background:transparent;color:#376a50}.phone{width:393px;height:852px;box-shadow:0 18px 60px #21342616;border-radius:28px;overflow:hidden;background:#fafaf7;outline:6px solid #fff;flex:none}.phone svg{display:block;width:100%;height:100%}.phone a{cursor:pointer}.phone a:focus{outline:2px solid #376a50}.caption{max-width:480px;text-align:center;font-size:12px;color:#606d63;line-height:1.6;margin-top:10px}.toast{position:fixed;bottom:30px;left:50%;transform:translateX(-50%);border-radius:14px;padding:14px 22px;color:white;background:#202d26;font-size:13px;box-shadow:0 8px 32px #0002;z-index:9;display:none}.gallery{display:grid;grid-template-columns:repeat(5,1fr);gap:24px;padding:32px}.gallery figure{margin:0}.gallery svg{width:100%;height:auto;box-shadow:0 8px 30px #0001}.gallery figcaption{font-size:13px;margin-bottom:12px}.gallery a{pointer-events:none}body.gallery-mode .layout{display:none}#gallery{display:none}body.gallery-mode #gallery{display:block}.gallery-head{padding:34px 32px 0;display:flex;justify-content:space-between;align-items:center}.gallery-head button{padding:10px 18px;border-radius:25px;background:#376a50;color:white;border:0}@media(max-width:760px){.layout{display:block}aside{display:none}.stage{padding:22px 10px}.phone{width:min(393px,calc(100vw - 28px));height:auto;aspect-ratio:393/852}.top{padding:0 12px}.gallery{grid-template-columns:repeat(2,1fr)}}@media(prefers-reduced-motion:no-preference){.phone{transition:box-shadow .2s}button{transition:background .15s}}
</style></head><body><div class="layout"><aside><div class="eyebrow">THE READER / iOS</div><h1>A quiet place<br>for every story.</h1><p>A personal library.<br>A world of connected sources.</p><div class="screenlist" id="screenlist"></div><p style="font-size:11px;margin-top:26px">Design prototype · Sample content<br>Tap through the main flows.</p></aside><main class="stage"><div class="top"><span id="title">Home</span><button id="overview">All screens ↗</button></div><div class="phone" id="phone"></div><div class="caption" id="caption"></div></main></div><div id="gallery"><div class="gallery-head"><div><div class="eyebrow">THE READER / DESIGN SYSTEM</div><h1>Every story. One place.</h1></div><button id="closeGallery">Open prototype</button></div><div class="gallery" id="galleryItems"></div></div><div class="toast" role="status" id="toast"></div><script>
const screens=__SCREENS__;const meta=__META__;const list=document.getElementById('screenlist');let current='home';
const mainIds=__MAIN__;
for(const [i,key] of mainIds.entries()){const m=meta.find(x=>x.id===key);const b=document.createElement('button');b.innerHTML='<span class="num">'+String(i+1).padStart(2,'0')+'</span>'+m.title;b.dataset.id=key;b.onclick=()=>show(key);list.appendChild(b)}
function show(id){if(!screens[id])return action(id);current=id;const m=meta.find(x=>x.id===id);document.getElementById('phone').innerHTML=screens[id];document.getElementById('title').textContent=m.title;document.getElementById('caption').textContent=m.description;for(const b of list.children)b.classList.toggle('active',b.dataset.id===id);history.replaceState(null,'','#'+id)}
let timer;function toast(t){const el=document.getElementById('toast');el.textContent=t;el.style.display='block';clearTimeout(timer);timer=setTimeout(()=>el.style.display='none',2600)}
function action(id){const t={'app-lock':'App lock settings · Face ID and device passcode','backup':'Backup includes your library, edits, covers and reading progress.','extension-toggle':'Extension state can be changed here.','extension-refresh':'All three extensions are up to date.','extension-add':'Add a trusted extension repository.','category-add':'Create and name a new library category.','cover-picker':'Choose a replacement cover from Photos or Files.','clear-cache':'Temporary cache cleared. Downloads are preserved.','download-pause':'Download queue paused.','reader-mode':'Reading mode selected for this preview.','reader-setting':'Reader setting selected.','next-chapter':'Next: Chapter 21 · MangaSee'};toast(t[id]||'Preview action')}
document.getElementById('phone').addEventListener('click',e=>{const a=e.target.closest('a[data-target]');if(a){e.preventDefault();show(a.dataset.target)}});
document.getElementById('overview').onclick=()=>{document.body.classList.add('gallery-mode');window.scrollTo(0,0)};document.getElementById('closeGallery').onclick=()=>document.body.classList.remove('gallery-mode');
for(const key of mainIds){const m=meta.find(x=>x.id===key);const f=document.createElement('figure');const cap=document.createElement('figcaption');cap.textContent=m.title;f.appendChild(cap);f.insertAdjacentHTML('beforeend',screens[key]);document.getElementById('galleryItems').appendChild(f)}
document.addEventListener('keydown',e=>{if(e.key==='Escape')document.body.classList.remove('gallery-mode')});show(screens[location.hash.slice(1)]?location.hash.slice(1):'home');
</script></body></html>'''.replace('__SCREENS__',data).replace('__META__',meta).replace('__MAIN__',json.dumps(main))
    (ROOT/'manga-reader-preview.html').write_text(html)
    print(json.dumps({'screens':len(SCREENS),'boardScreens':len(main),'boardDimensions':[bw,bh],'root':str(ROOT)}))
if __name__=='__main__':output()
