# -*- coding: utf-8 -*-
"""
말길 · 법정동(lDong) 시도·시군구 코드 목록 pull  (TourAPI 4.0 KorService2 / ldongCode2)

  왜 필요한가
    급수 판정의 「기초지자체 집합」을 공사 API가 지금 쓰는 코드 체계 그대로 고정하기 위해서다.
    2026-07-01 개편으로 광주·전남이 12xxx로, 인천 중구·동구·서구가 제물포·영종·서해·검단구로
    바뀌었다. 방문자 원장(c1_visitor_raw.json)이나 인구 CSV의 코드를 기준으로 삼으면
    구코드·신코드가 섞인다. 이 목록이 유일한 기준(마스터)이다.

  호출  ① lDongRegnCd 없이 1회 → 시도 16개 (세종은 code가 5자리 36110으로 온다)
        ② 시도마다 1회 → 시군구 목록. 합계 17회 (한도 1,000회/일 대비 미미)
  응답  items.item[] = {rnum, code, name}   (2026-09-14 실호출로 확인)
        시군구 code는 3자리(lDongSignguCd) → 시도 2자리 + 3자리 = 행정표준코드 5자리

  parent  일반구(code[-1] != '0')이고 code[:4]+'0'가 같은 시도 목록에 있으면 그 시 코드.
          예) 수원시 장안구 41111 → 41110. 자치구(서울 종로구 11110)는 부모가 없어 자기 자신.
          세종 36110 → 36110.

  출력  _raw/ldong_269.json  (pull_* 규칙: _raw 에만 쓴다. 사람이 읽는 짝 산출물 없음)
  실행  python data/AI/pull_ldong.py
"""
import io, os, sys, json, time, datetime, urllib.request, urllib.parse

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
ROOT = os.path.dirname(os.path.dirname(HERE))             # 프로젝트 루트 (.env)
BASE = "https://apis.data.go.kr/B551011/KorService2/ldongCode2"
CALLS = 0


def load_key():
    """프로젝트 루트 .env 에서 인증키를 읽는다 (.env 는 .gitignore 대상). 값은 절대 출력하지 않는다."""
    p = os.path.join(ROOT, ".env")
    env = {}
    if os.path.exists(p):
        for line in io.open(p, encoding="utf-8-sig"):
            line = line.strip()
            if line and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    key = env.get("Api_Key_Decoding") or os.environ.get("TOUR_API_KEY", "")
    if not key:
        raise SystemExit(".env 에 Api_Key_Decoding 이 없습니다")
    return key


KEY = load_key()


def fetch(regn=None):
    global CALLS
    q = {"MobileOS": "ETC", "MobileApp": "malgil", "_type": "json",
         "numOfRows": 500, "pageNo": 1}
    if regn:
        q["lDongRegnCd"] = regn
    url = "%s?serviceKey=%s&%s" % (BASE, urllib.parse.quote(KEY, safe=""), urllib.parse.urlencode(q))
    CALLS += 1
    raw = urllib.request.urlopen(
        urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60
    ).read().decode("utf-8", "replace")
    j = json.loads(raw)
    if "response" not in j:                      # TSD §4-4 — 파라미터 오류는 래퍼 없이 온다
        raise RuntimeError("%s %s" % (j.get("resultCode"), j.get("resultMsg")))
    hdr = j["response"].get("header", {})
    if hdr.get("resultCode") not in ("0000", "00"):
        raise RuntimeError("%s %s" % (hdr.get("resultCode"), hdr.get("resultMsg")))
    it = j["response"].get("body", {}).get("items") or {}
    arr = it.get("item", []) if isinstance(it, dict) else []
    if isinstance(arr, dict):
        arr = [arr]
    return [{"code": str(x.get("code", "")), "name": str(x.get("name", "")).strip()} for x in arr]


def main():
    sido = fetch()
    print("시도 %d개" % len(sido))
    sgg = []
    for s in sido:
        rows = fetch(s["code"])
        time.sleep(0.2)
        for r in rows:
            c = r["code"]
            if len(c) == 3:
                code5 = s["code"][:2] + c
            elif len(c) == 5:
                code5 = c
            else:
                print("  ?? 코드 형식 이상", s, r)
                continue
            sgg.append({"code5": code5, "sido": s["name"], "nm": r["name"]})
        print("  %-5s %-12s %3d곳" % (s["code"], s["name"], len(rows)))

    # parent — 일반구는 시로. 같은 시도 안에서 code[:4]+'0'가 있고, 이름이 「그 시 이름 + 공백」으로
    # 시작할 때만. 코드만 보면 증평군 43745 가 영동군 43740 의 구로 잡힌다 (2026-09-14 실측) —
    # 이름 조건이 그것을 막는다. 예) 「청주시 상당구」 43111 → 청주시 43110
    names = {x["code5"]: x["nm"] for x in sgg}
    n_gu = 0
    for x in sgg:
        c = x["code5"]
        p = c[:4] + "0"
        if c[-1] != "0" and p in names and p != c and x["nm"].startswith(names[p] + " "):
            x["parent"] = p
            n_gu += 1
        else:
            x["parent"] = c
    parents = {x["parent"] for x in sgg}
    print("시군구 %d개 (일반구 %d개 → 병합 후 %d개)" % (len(sgg), n_gu, len(parents)))

    p = os.path.join(RAW, "ldong_269.json")
    json.dump({"operation": "KorService2/ldongCode2",
               "pulled_at": datetime.date.today().isoformat(),
               "calls": CALLS,
               "n_sido": len(sido), "n_sgg": len(sgg), "n_gu": n_gu, "n_base": len(parents),
               "시도": sido,
               "시군구": sgg},
              open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("%d회 호출 → %s" % (CALLS, p))


if __name__ == "__main__":
    main()
