# -*- coding: utf-8 -*-
"""
말길 · C-1 지역별 방문자수 pull  (한국관광공사_빅데이터_지역별 방문자수_GW)

  확정 스펙 (2026-09-07 실호출로 검증)
    엔드포인트  https://apis.data.go.kr/B551011/DataLabService/locgoRegnVisitrDDList
    파라미터    startYmd · endYmd (YYYYMMDD) · numOfRows · pageNo · MobileOS · MobileApp · _type
    응답 필드   signguCode(행정표준코드 5자리) · signguNm · daywkDivCd/Nm(요일)
                touDivCd/Nm(1 현지인(a) · 2 외지인(b) · 3 외국인(c)) · touNum · baseYmd
    특성        지역 필터 파라미터 없이 전국 264개 시군구가 한 번에 나온다
                하루치 = 264 시군구 × 3 구분 = 792행. numOfRows 최대 10,000 확인
    광역판      metcoRegnVisitrDDList (areaCode/areaNm) — 말길은 기초(locgo)를 쓴다

  ⛔ 해석 금지 (계획서 §5-5)
    P-DL01 총량 사용 금지 — 추세 · 구성비로만
    P-DL02 기초 ↔ 광역 임의 합산 금지
    P-DL03 「방문자」 ≠ 「관광객」

  실행  python pull_visitor.py            (기본 2025-08 ~ 2026-07)
        python pull_visitor.py 202508 202607
"""
import io, os, sys, json, time, urllib.request, urllib.parse

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
ROOT = os.path.dirname(HERE)
OP = "locgoRegnVisitrDDList"
BASE = "https://apis.data.go.kr/B551011/DataLabService"
ROWS = 10000
CALLS = 0


def load_key():
    """프로젝트 루트 .env 에서 인증키를 읽는다 (.env 는 .gitignore 대상)."""
    p = os.path.join(ROOT, ".env")
    env = {}
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


def fetch(start, end, page):
    global CALLS
    q = {"MobileOS": "ETC", "MobileApp": "malgil", "_type": "json",
         "startYmd": start, "endYmd": end, "numOfRows": ROWS, "pageNo": page}
    url = "%s/%s?serviceKey=%s&%s" % (BASE, OP, urllib.parse.quote(KEY, safe=""),
                                      urllib.parse.urlencode(q))
    CALLS += 1
    raw = urllib.request.urlopen(
        urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}),
        timeout=60).read().decode("utf-8", "replace")
    body = json.loads(raw)["response"]
    hdr = body.get("header", {})
    if hdr.get("resultCode") not in ("0000", "00"):
        raise RuntimeError("%s %s" % (hdr.get("resultCode"), hdr.get("resultMsg")))
    b = body.get("body", {})
    it = b.get("items") or {}
    arr = it.get("item", []) if isinstance(it, dict) else it
    if isinstance(arr, dict):
        arr = [arr]
    return int(b.get("totalCount", 0) or 0), (arr or [])


def months(start_ym, end_ym):
    y, m = int(start_ym[:4]), int(start_ym[4:])
    ey, em = int(end_ym[:4]), int(end_ym[4:])
    while (y, m) <= (ey, em):
        yield "%04d%02d" % (y, m)
        m += 1
        if m == 13:
            y, m = y + 1, 1


def last_day(ym):
    y, m = int(ym[:4]), int(ym[4:])
    if m == 12:
        ny, nm = y + 1, 1
    else:
        ny, nm = y, m + 1
    import datetime
    return (datetime.date(ny, nm, 1) - datetime.timedelta(days=1)).strftime("%Y%m%d")


def main():
    s_ym = sys.argv[1] if len(sys.argv) > 2 else "202508"
    e_ym = sys.argv[2] if len(sys.argv) > 2 else "202607"
    out = []
    print("C-1 방문자수 pull — %s ~ %s (기초지자체 %s)" % (s_ym, e_ym, OP))
    for ym in months(s_ym, e_ym):
        start, end = ym + "01", last_day(ym)
        got, page = [], 1
        while True:
            total, arr = fetch(start, end, page)
            got.extend(arr)
            if len(got) >= total or not arr:
                break
            page += 1
            time.sleep(0.2)
        days = len(set(x["baseYmd"] for x in got))
        print("  %s  %6d행 / %d일 / %d페이지%s"
              % (ym, len(got), days, page, "  ⚠️불완전" if days < 28 else ""))
        out.extend(got)
        time.sleep(0.2)
    p = os.path.join(RAW, "c1_visitor_raw.json")
    json.dump({"operation": OP, "window": "%s~%s" % (s_ym, e_ym),
               "pulled_at": "2026-09-07", "n": len(out), "items": out},
              open(p, "w", encoding="utf-8"), ensure_ascii=False)
    print("\n총 %d행 · %d회 호출 → %s" % (len(out), CALLS, p))
    print("⚠️ P-DL01 — 이 값은 추세 · 구성비로만 사용합니다. 총량 인용 금지")


if __name__ == "__main__":
    main()
