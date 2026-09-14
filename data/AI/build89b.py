# -*- coding: utf-8 -*-
import json,io,sys

import os
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding="utf-8")
cn=json.load(open(os.path.join(RAW, "code_name.json"),encoding="utf-8"))
# name -> codes
idx={}
for k,(sido,sgg,n) in cn.items():
    idx.setdefault((sido,sgg),[]).append(k)

DECL={
 "부산광역시":["동구","서구","영도구"],
 "대구광역시":["남구","서구","군위군"],
 "인천광역시":["강화군","옹진군"],
 "경기도":["가평군","연천군"],
 "강원특별자치도":["고성군","삼척시","양구군","양양군","영월군","정선군","철원군","태백시","평창군","홍천군","화천군","횡성군"],
 "충청북도":["괴산군","단양군","보은군","영동군","옥천군","제천시"],
 "충청남도":["공주시","금산군","논산시","보령시","부여군","서천군","예산군","청양군","태안군"],
 "전북특별자치도":["고창군","김제시","남원시","무주군","부안군","순창군","임실군","장수군","정읍시","진안군"],
 "전남광주통합특별시":["강진군","고흥군","곡성군","구례군","담양군","보성군","신안군","영광군","영암군","완도군","장성군","장흥군","진도군","함평군","해남군","화순군"],
 "경상북도":["고령군","문경시","봉화군","상주시","성주군","안동시","영덕군","영양군","영주시","영천시","울릉군","울진군","의성군","청도군","청송군"],
 "경상남도":["거창군","고성군","남해군","밀양시","산청군","의령군","창녕군","하동군","함안군","함양군","합천군"],
}
INTEREST={
 "대전광역시":["동구","중구","대덕구"],
 "인천광역시":["제물포구"],
 "부산광역시":["중구","금정구"],
 "전남광주통합특별시":["동구"],
 "경상남도":["통영시","사천시"],
 "강원특별자치도":["강릉시","동해시","인제군","속초시"],
 "경상북도":["경주시","김천시"],
 "전북특별자치도":["익산시"],
 "경기도":["동두천시","포천시"],
}
def resolve(tbl,label):
    out=[];bad=[]
    for sido,lst in tbl.items():
        for sgg in lst:
            ks=idx.get((sido,sgg))
            if not ks: bad.append((sido,sgg));continue
            k=sorted(ks,key=lambda x:-cn[x][2])[0]
            out.append({"code":k,"sido":sido,"sgg":sgg})
    print(label,len(out),"unmatched:",bad)
    return out
d=resolve(DECL,"DECL"); i=resolve(INTEREST,"INTEREST")
json.dump({"decline":d,"interest":i},open(os.path.join(RAW, "regions.json"),"w",encoding="utf-8"),ensure_ascii=False,indent=1)
for x in d: print(x["code"],x["sido"],x["sgg"])
