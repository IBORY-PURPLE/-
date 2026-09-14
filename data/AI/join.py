# -*- coding: utf-8 -*-
import json,collections,io,sys
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding="utf-8")
d=json.load(open(os.path.join(RAW, "dump.json"),encoding="utf-8"))
reg=json.load(open(os.path.join(RAW, "regions.json"),encoding="utf-8"))
cn=json.load(open(os.path.join(RAW, "code_name.json"),encoding="utf-8"))
def key(r):
    a=(r.get("lDongRegnCd") or "")+(r.get("lDongSignguCd") or "")
    return a if len(a)==5 else None
K=collections.Counter(); E=collections.Counter()
KF=collections.Counter(); EF=collections.Counter()
ktype=collections.Counter(); etype=collections.Counter()
for r in d["KorService2"]["items"]:
    ktype[r.get("contenttypeid")]+=1
    k=key(r)
    if not k: continue
    K[k]+=1
    if r.get("contenttypeid")=="39": KF[k]+=1
for r in d["EngService2"]["items"]:
    etype[r.get("contenttypeid")]+=1
    k=key(r)
    if not k: continue
    E[k]+=1
    if r.get("contenttypeid")=="82": EF[k]+=1
print("KOR types",sorted(ktype.items(),key=lambda x:-x[1]))
print("ENG types",sorted(etype.items(),key=lambda x:-x[1]))
D={x["code"]:x for x in reg["decline"]}
I={x["code"]:x for x in reg["interest"]}
allcodes=set(K)|set(E)
def agg(codes,label):
    k=sum(K[c] for c in codes); e=sum(E[c] for c in codes)
    kf=sum(KF[c] for c in codes); ef=sum(EF[c] for c in codes)
    print(f"{label}: n={len(codes)} KOR={k:,} ENG={e:,} cover={e/k*100:.2f}%  KOR음식={kf:,} ENG음식={ef:,} 음식cover={ef/kf*100 if kf else 0:.2f}%")
    return dict(n=len(codes),kor=k,eng=e,cover=e/k*100,korf=kf,engf=ef,coverf=(ef/kf*100 if kf else 0))
res={}
res["decline"]=agg(set(D),"인구감소지역89")
res["interest"]=agg(set(I),"관심지역18")
res["other"]=agg(allcodes-set(D)-set(I),"비89·비관심")
res["nation"]=agg(allcodes,"전국(코드보유분)")
# 수도권 정의
CAP={c for c in allcodes if c[:2] in ("11","41","28")}
res["capital"]=agg(CAP,"수도권(서울인천경기)")
res["noncap_nondecl"]=agg(allcodes-CAP-set(D)-set(I),"비수도권·비89·비관심")
# 지역별 표
rows=[]
for c in sorted(D):
    kr,en=K[c],E[c]
    rows.append((c,D[c]["sido"],D[c]["sgg"],kr,en,(en/kr*100 if kr else 0),KF[c],EF[c],(EF[c]/KF[c]*100 if KF[c] else 0)))
rows.sort(key=lambda r:-r[5])
print("\n=== 89곳 영문 커버율 상위 15 ===")
for r in rows[:15]: print(f"{r[0]} {r[1][:2]} {r[2]:6s} KOR{r[3]:5d} ENG{r[4]:4d} {r[5]:6.2f}%  음식 {r[6]:4d}/{r[7]:3d} {r[8]:6.2f}%")
print("=== 89곳 영문 커버율 하위 15 ===")
for r in rows[-15:]: print(f"{r[0]} {r[1][:2]} {r[2]:6s} KOR{r[3]:5d} ENG{r[4]:4d} {r[5]:6.2f}%  음식 {r[6]:4d}/{r[7]:3d} {r[8]:6.2f}%")
# 전국 시군구 커버율 순위 (KOR>=50)
allrows=[]
for c in allcodes:
    if K[c]<50: continue
    nm=cn.get(c,["?","?",0])
    allrows.append((c,nm[0],nm[1],K[c],E[c],E[c]/K[c]*100, c in D, c in I))
allrows.sort(key=lambda r:-r[5])
print("\n=== 전국 시군구(국문50건이상) 커버율 상위 20 ===")
for r in allrows[:20]: print(f"{r[0]} {r[1][:6]:8s}{r[2]:7s} KOR{r[3]:5d} ENG{r[4]:5d} {r[5]:6.2f}% {'[89]' if r[6] else ('[관심]' if r[7] else '')}")
print("=== 전국 시군구 커버율 하위 20 ===")
for r in allrows[-20:]: print(f"{r[0]} {r[1][:6]:8s}{r[2]:7s} KOR{r[3]:5d} ENG{r[4]:5d} {r[5]:6.2f}% {'[89]' if r[6] else ('[관심]' if r[7] else '')}")
n89=sum(1 for r in allrows if r[6])
print(f"\n국문50건이상 시군구 {len(allrows)}개 중 89곳 {n89}개")
# 중앙값
import statistics

import os
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
d89=[r[5] for r in allrows if r[6]]; dno=[r[5] for r in allrows if not r[6] and not r[7]]
print(f"커버율 중앙값 89곳={statistics.median(d89):.2f}% / 비89비관심={statistics.median(dno):.2f}%")
print(f"커버율 평균(단순) 89곳={statistics.mean(d89):.2f}% / 비89비관심={statistics.mean(dno):.2f}%")
json.dump({"summary":res,"rows89":rows,"allrows":allrows},open(os.path.join(RAW, "join_result.json"),"w",encoding="utf-8"),ensure_ascii=False,indent=1)
