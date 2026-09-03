# -*- coding: utf-8 -*-
import json, time, urllib.request, urllib.parse, sys, re, os
KEY=os.environ.get("TOUR_API_KEY","")
if not KEY:
    sys.exit("TOUR_API_KEY is not set. Export your Korea Tourism Organization OpenAPI service key (decoded) first.")
BASE="https://apis.data.go.kr/B551011"
ROWS=1000
def fetch(svc,page,rows=ROWS):
    q={"serviceKey":KEY,"MobileOS":"ETC","MobileApp":"malgil","_type":"json",
       "numOfRows":rows,"pageNo":page}
    url=f"{BASE}/{svc}/areaBasedList2?"+urllib.parse.urlencode(q,safe="%")
    req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0"})
    with urllib.request.urlopen(req,timeout=60) as r:
        raw=r.read().decode("utf-8","replace")
    if not raw.lstrip().startswith("{"):
        m=re.search(r"<(?:returnAuthMsg|errMsg|resultMsg)>(.*?)</",raw)
        raise RuntimeError(m.group(1) if m else raw[:200])
    b=json.loads(raw)["response"]["body"]
    it=b.get("items") or {}
    arr=it.get("item",[]) if isinstance(it,dict) else []
    if isinstance(arr,dict): arr=[arr]
    return b.get("totalCount",0), arr

def collect(svc):
    total,first=fetch(svc,1)
    out=list(first)
    pages=(total+ROWS-1)//ROWS
    sys.stderr.write(f"{svc}: total={total} pages={pages}\n")
    for p in range(2,pages+1):
        for a in range(4):
            try:
                _,arr=fetch(svc,p); out.extend(arr); break
            except Exception as e:
                sys.stderr.write(f" p{p} try{a} fail {e}\n"); time.sleep(2)
        time.sleep(0.1)
    sys.stderr.write(f"{svc}: got {len(out)}\n")
    return total,out

slim=lambda r:{k:r.get(k,"") for k in("contentid","contenttypeid","title","addr1","lDongRegnCd","lDongSignguCd","areacode","sigungucode","lclsSystm1","lclsSystm2")}
res={}
for svc in ("KorService2","EngService2"):
    t,rows=collect(svc)
    res[svc]={"total":t,"fetched":len(rows),"items":[slim(r) for r in rows]}
json.dump(res,open("dump.json","w",encoding="utf-8"),ensure_ascii=False)
print("DONE", {k:(v["total"],v["fetched"]) for k,v in res.items()})
