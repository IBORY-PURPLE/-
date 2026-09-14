# -*- coding: utf-8 -*-
import json,collections,io,sys,statistics

import os
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding="utf-8")
d=json.load(open(os.path.join(RAW, "dump.json"),encoding="utf-8"))
reg=json.load(open(os.path.join(RAW, "regions.json"),encoding="utf-8"))
cn=json.load(open(os.path.join(RAW, "code_name.json"),encoding="utf-8"))
D={x["code"]:x for x in reg["decline"]}; I={x["code"]:x for x in reg["interest"]}
def key(r):
    a=(r.get("lDongRegnCd") or "")+(r.get("lDongSignguCd") or ""); return a if len(a)==5 else None
K=collections.Counter();E=collections.Counter();Kns=collections.Counter();Ens=collections.Counter()
trs=collections.Counter()  # tax refund shop
for r in d["KorService2"]["items"]:
    k=key(r)
    if not k: continue
    K[k]+=1
    if r.get("contenttypeid")!="38": Kns[k]+=1
for r in d["EngService2"]["items"]:
    k=key(r)
    if not k: continue
    E[k]+=1
    if r.get("contenttypeid")!="79": Ens[k]+=1
    if "[Tax Refund Shop]" in (r.get("title") or ""): trs[k]+=1
allc=set(K)|set(E)
def agg(cs,label):
    k=sum(K[c] for c in cs);e=sum(E[c] for c in cs)
    kn=sum(Kns[c] for c in cs);en=sum(Ens[c] for c in cs);t=sum(trs[c] for c in cs)
    print(f"{label:22s} KOR{k:6,} ENG{e:6,} {e/k*100:6.2f}% | 쇼핑제외 KOR{kn:6,} ENG{en:5,} {en/kn*100:6.2f}% | TaxRefund {t:5,}")
print("총 TaxRefund:",sum(trs.values()))
agg(set(D),"인구감소89"); agg(set(I),"관심18")
agg(allc-set(D)-set(I),"비89비관심")
CAP={c for c in allc if c[:2] in("11","41","28")}
agg(CAP,"수도권"); agg(allc-CAP-set(D)-set(I),"비수도권·비89비관심"); agg(allc,"전국")
print()
for nm,code in [("하남","41450"),("남양주","41360"),("동해","51170"),("철원","51780"),("가평","41820"),("연천","41800")]:
    print(f"{nm} {code} KOR{K[code]} ENG{E[code]} {E[code]/K[code]*100 if K[code] else 0:.2f}% 쇼핑제외 {Kns[code]}/{Ens[code]} {Ens[code]/Kns[code]*100 if Kns[code] else 0:.2f}% TRS{trs[code]}")
# 전통시장 앵커
mk=collections.Counter(); mknames=collections.defaultdict(list)
for r in d["KorService2"]["items"]:
    t=r.get("title") or ""; k=key(r)
    if not k: continue
    if "시장" in t or "5일장" in t or "오일장" in t:
        mk[k]+=1; mknames[k].append(t)
n89=sum(1 for c in D if mk[c]>0)
print(f"\n전통시장/장 키워드 보유 89곳: {n89}/89 (총 {sum(mk[c] for c in D)}건)")
print("무보유:",[f"{D[c]['sgg']}" for c in D if mk[c]==0])
# 상관: 89 vs 나머지 통계검정 (Mann-Whitney 대용 - 순위)
r89=[E[c]/K[c]*100 for c in allc if c in D and K[c]>=50]
rot=[E[c]/K[c]*100 for c in allc if c not in D and c not in I and K[c]>=50]
print(f"\nn89={len(r89)} median={statistics.median(r89):.2f} mean={statistics.mean(r89):.2f}")
print(f"nOther={len(rot)} median={statistics.median(rot):.2f} mean={statistics.mean(rot):.2f}")
# 몇 %의 89곳이 전국 하위 4분위에 있나
allr=sorted([(E[c]/K[c]*100,c) for c in allc if K[c]>=50])
q1=allr[:len(allr)//4]
print(f"전국 하위25%({len(q1)}개) 중 89곳: {sum(1 for _,c in q1 if c in D)}개")
q4=allr[-len(allr)//4:]
print(f"전국 상위25%({len(q4)}개) 중 89곳: {sum(1 for _,c in q4 if c in D)}개")
json.dump({"K":dict(K),"E":dict(E),"Kns":dict(Kns),"Ens":dict(Ens),"trs":dict(trs),"mk":dict(mk)},open(os.path.join(RAW, "deep.json"),"w",encoding="utf-8"),ensure_ascii=False)
