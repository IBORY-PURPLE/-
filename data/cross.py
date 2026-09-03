# -*- coding: utf-8 -*-
import csv,json,io,sys,re,statistics,math
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding="utf-8")
rows=list(csv.reader(open("age_sgg_utf8.csv",encoding="utf-8")))
hdr=rows[0]; n=lambda s:int(s.replace(",","")) if s.replace(",","").isdigit() else 0
def idxs(pat): return [i for i,h in enumerate(hdr) if re.match(pat,h)]
i65=idxs(r'.*_계_(6[5-9]|7\d|8\d|9\d)~|.*_계_100세')
i5074=idxs(r'.*_계_(5[05]|6[05]|7[0])~')
itot=hdr.index([h for h in hdr if h.endswith("_계_총인구수")][0])
A={}
for r in rows[1:]:
    m=re.search(r'\((\d{10})\)',r[0])
    if not m: continue
    A[m.group(1)[:5]]={"name":r[0].split("(")[0].strip(),"pop":n(r[itot]),
      "o65":sum(n(r[i]) for i in i65),"a5074":sum(n(r[i]) for i in i5074)}
tour=json.load(open("deep.json",encoding="utf-8"))
K,E,Kns,Ens=tour["K"],tour["E"],tour["Kns"],tour["Ens"]
reg=json.load(open("regions.json",encoding="utf-8"))
D={x["code"]:x for x in reg["decline"]}; I={x["code"]:x for x in reg["interest"]}
g=lambda d,c:d.get(c,0)
p89=sum(A[c]["pop"] for c in D); a89=sum(A[c]["a5074"] for c in D); o89=sum(A[c]["o65"] for c in D)
tp=sum(v["pop"] for k,v in A.items() if k[2:]=="000"); ta=sum(v["a5074"] for k,v in A.items() if k[2:]=="000")
print(f"89곳 50~74세 {a89:,} ({a89/p89*100:.1f}%)  전국 50~74 {ta:,} ({ta/tp*100:.1f}%)")
print(f"89곳 65+ {o89:,} ({o89/p89*100:.2f}%)")
# 상관
pts=[]
for c,v in A.items():
    if c[2:]=="000": continue
    if g(K,c)<50: continue
    pts.append((v["o65"]/v["pop"]*100, g(E,c)/g(K,c)*100, g(Ens,c)/g(Kns,c)*100 if g(Kns,c) else None, c))
def pear(xs,ys):
    mx,my=statistics.mean(xs),statistics.mean(ys)
    num=sum((a-mx)*(b-my) for a,b in zip(xs,ys))
    den=math.sqrt(sum((a-mx)**2 for a in xs)*sum((b-my)**2 for b in ys))
    return num/den
xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
print(f"\n[전국 {len(pts)}개 시군구, 국문>=50] 고령화율 vs 영문커버율(전체)  r={pear(xs,ys):+.3f}")
q=[p for p in pts if p[2] is not None]
print(f"[{len(q)}개] 고령화율 vs 영문커버율(쇼핑제외)      r={pear([p[0] for p in q],[p[2] for p in q]):+.3f}")
# 89 내부
p9=[p for p in pts if p[3] in D]
print(f"[89곳 {len(p9)}개] 고령화율 vs 영문커버율(전체)     r={pear([p[0] for p in p9],[p[1] for p in p9]):+.3f}")
# 4분면
med_age=statistics.median(xs); med_cov=statistics.median(ys)
print(f"\n중앙값: 고령화율 {med_age:.1f}% / 영문커버율 {med_cov:.1f}%")
quad={"고령高·커버低":0,"고령高·커버高":0,"고령低·커버低":0,"고령低·커버高":0}
q89=dict(quad)
for a,b,_,c in pts:
    k=("고령高" if a>=med_age else "고령低")+("·커버低" if b<med_cov else "·커버高")
    quad[k]+=1
    if c in D: q89[k]+=1
print("전국 4분면",quad); print("89곳 4분면",q89)
# 최종 89 표
tab=[]
mk=json.load(open("anchor.json",encoding="utf-8"))["mk"]
for c,x in D.items():
    v=A[c]
    tab.append({"code":c,"sido":x["sido"],"sgg":x["sgg"],"pop":v["pop"],
      "old_rate":round(v["o65"]/v["pop"]*100,1),"a5074":v["a5074"],
      "kor":g(K,c),"eng":g(E,c),"cov":round(g(E,c)/g(K,c)*100,1) if g(K,c) else 0,
      "kor_ns":g(Kns,c),"eng_ns":g(Ens,c),
      "cov_ns":round(g(Ens,c)/g(Kns,c)*100,1) if g(Kns,c) else 0,
      "market":mk.get(c,0)})
tab.sort(key=lambda r:-r["old_rate"])
json.dump(tab,open("table89.json","w",encoding="utf-8"),ensure_ascii=False,indent=1)
print(f"\n=== 89곳 상위 12 (고령화율 순) ===")
print(f"{'코드':6s}{'지역':14s}{'인구':>9s}{'65+%':>7s}{'50-74':>8s}{'국문':>6s}{'영문':>6s}{'커버%':>7s}{'시장':>5s}")
for r in tab[:12]:
    print(f"{r['code']:6s}{(r['sido'][:2]+' '+r['sgg']):14s}{r['pop']:9,}{r['old_rate']:7.1f}{r['a5074']:8,}{r['kor']:6d}{r['eng']:6d}{r['cov']:7.1f}{r['market']:5d}")
