# -*- coding: utf-8 -*-
import csv,json,io,sys,re,statistics

import os
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding="utf-8")
rows=list(csv.reader(open(os.path.join(RAW, "age_sgg_utf8.csv"),encoding="utf-8")))
hdr=rows[0]
i65=[i for i,h in enumerate(hdr) if re.match(r'.*_계_(6[5-9]|7\d|8\d|9\d)~|.*_계_100세',h)]
itot=hdr.index([h for h in hdr if h.endswith("_계_총인구수")][0])
A={}
for r in rows[1:]:
    m=re.search(r'\((\d{10})\)',r[0])
    if not m: continue
    code=m.group(1); name=r[0].split("(")[0].strip()
    n=lambda s:int(s.replace(",","")) if s.replace(",","").isdigit() else 0
    tot=n(r[itot]); old=sum(n(r[i]) for i in i65)
    A[code[:5]]={"name":name,"pop":tot,"old":old,"rate":old/tot*100 if tot else 0,"full":code}
print("rows",len(A))
nat=A.get("00000")
# 전국 = sum of sido rows (codes ending 00000 pattern: xx000)
sido={k:v for k,v in A.items() if k[2:]=="000"}
tp=sum(v["pop"] for v in sido.values()); to=sum(v["old"] for v in sido.values())
print(f"전국(시도합) 인구 {tp:,} / 65+ {to:,} = {to/tp*100:.2f}%  [2026-08 주민등록]")
reg=json.load(open(os.path.join(RAW, "regions.json"),encoding="utf-8"))
D=reg["decline"]; I=reg["interest"]
miss=[x for x in D if x["code"] not in A]
print("89 unmatched:",miss)
d89=[(x["code"],x["sido"],x["sgg"],A[x["code"]]["pop"],A[x["code"]]["rate"]) for x in D if x["code"] in A]
d18=[(x["code"],x["sido"],x["sgg"],A[x["code"]]["pop"],A[x["code"]]["rate"]) for x in I if x["code"] in A]
p89=sum(r[3] for r in d89); o89=sum(A[r[0]]["old"] for r in d89)
print(f"89곳 합계 인구 {p89:,} ({p89/tp*100:.1f}% of 전국) / 65+ {o89:,} = {o89/p89*100:.2f}%")
p18=sum(r[3] for r in d18); o18=sum(A[r[0]]["old"] for r in d18)
print(f"18곳 합계 인구 {p18:,} / 65+ {o18:,} = {o18/p18*100:.2f}%")
codes89={x["code"] for x in D}; codes18={x["code"] for x in I}
# 나머지 시군구 (일반구 제외 어려움 → 시도합 - 89 - 18)
rp=tp-p89-p18; ro=to-o89-o18
print(f"비89·비관심 인구 {rp:,} / 65+ {ro:,} = {ro/rp*100:.2f}%")
rr=[r[4] for r in d89]
print(f"89곳 고령화율 중앙값 {statistics.median(rr):.2f}% 최소 {min(rr):.2f}% 최대 {max(rr):.2f}%")
print(f"89곳 중 고령화율 30% 이상: {sum(1 for x in rr if x>=30)}개 / 40% 이상: {sum(1 for x in rr if x>=40)}개 / 전국평균({to/tp*100:.1f}%) 미만: {sum(1 for x in rr if x<to/tp*100)}개")
d89.sort(key=lambda r:-r[4])
print("\n고령화율 상위 10");  [print(f"  {r[0]} {r[1][:6]} {r[2]} pop {r[3]:,} {r[4]:.1f}%") for r in d89[:10]]
print("고령화율 하위 10");   [print(f"  {r[0]} {r[1][:6]} {r[2]} pop {r[3]:,} {r[4]:.1f}%") for r in d89[-10:]]
json.dump({"age":A,"d89":d89,"d18":d18,"nat":{"pop":tp,"old":to,"rate":to/tp*100}},open(os.path.join(RAW, "agejoin.json"),"w",encoding="utf-8"),ensure_ascii=False)
