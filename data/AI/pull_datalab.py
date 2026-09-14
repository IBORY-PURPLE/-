# -*- coding: utf-8 -*-
"""
말길 · 관광데이터랩 / 가치신호 API pull 스크립트
  Docs/plan/말길_데이터활용계획_v1.0.md §5 · §10 P0-2 / P0-3 / P0-3b 대응

사용법
  1) 인증키 설정 (디코딩된 키)
       PowerShell : $env:TOUR_API_KEY = "여기에키"
       bash       : export TOUR_API_KEY="여기에키"

  2) 오퍼레이션 탐침 — 명세 zip 없이 올바른 service/operation 조합을 찾는다
       python pull_datalab.py probe

  3) 확정된 조합으로 89곳 pull
       python pull_datalab.py pull center     # C-5 기초지자체 중심 관광지
       python pull_datalab.py pull audio      # C-7 관광지 오디오 가이드
       python pull_datalab.py pull visitor    # C-1 지역별 방문자수
       python pull_datalab.py pull rlte       # C-4 관광지별 연관 관광지
       python pull_datalab.py pull durunubi   # C-8 두루누비 코스

주의 (계획서 §5-5 P-DL)
  · 방문자수는 추세로만 쓴다. 총량 금지(P-DL01)
  · 기초 ↔ 광역 임의 합산 금지(P-DL02)
  · "방문자" ≠ "관광객"(P-DL03)
  · 개발계정 1,000회/일 — 호출 수를 세면서 돈다
"""
import json, os, re, sys, time, io, csv, urllib.request, urllib.parse, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8")

KEY = os.environ.get("TOUR_API_KEY", "")
BASE = "https://apis.data.go.kr/B551011"
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
CALLS = 0
CALL_BUDGET = 950          # 개발계정 1,000회에서 여유 50회

COMMON = {"MobileOS": "ETC", "MobileApp": "malgil", "_type": "json"}


def call(service, operation, params, timeout=30):
    """단건 호출. (ok, payload_or_errmsg) 반환. 호출 수를 전역으로 센다."""
    global CALLS
    if CALLS >= CALL_BUDGET:
        raise SystemExit("호출 예산 %d회 소진 — 오늘은 여기까지 (계획서 DP-2)" % CALL_BUDGET)
    q = dict(COMMON)
    q.update(params)
    q["serviceKey"] = KEY
    url = "%s/%s/%s?%s" % (BASE, service, operation, urllib.parse.urlencode(q, safe="%"))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    CALLS += 1
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
    except Exception as e:
        return False, "HTTP %s" % e
    if raw.lstrip().startswith("{"):
        try:
            body = json.loads(raw)["response"]
        except Exception:
            return False, "JSON parse fail: %s" % raw[:160]
        hdr = body.get("header", {})
        code = hdr.get("resultCode", "")
        if code not in ("0000", "00"):
            return False, "%s %s" % (code, hdr.get("resultMsg", ""))
        return True, body.get("body", {})
    m = re.search(r"<(?:returnAuthMsg|errMsg|resultMsg|returnReasonCode)>(.*?)</", raw)
    return False, (m.group(1) if m else raw[:160].replace("\n", " "))


def items_of(body):
    it = body.get("items") or {}
    if isinstance(it, str):
        return []
    arr = it.get("item", []) if isinstance(it, dict) else it
    if isinstance(arr, dict):
        arr = [arr]
    return arr or []


# ─────────────────────────────────────────────────────────────
# 1. 탐침 — 명세 zip 없이 올바른 조합 찾기
# ─────────────────────────────────────────────────────────────
# 확정: TarRlteTarService1/areaBasedList1 (C-4 연관 관광지)
#        — data.go.kr 15128560 검색으로 확인됨 (2026-09-07)
# 나머지는 후보를 넓게 깔고 resultCode=0000 이 뜨는 조합만 남긴다.
PROBES = {
    "center (C-5 기초지자체 중심 관광지)": [
        ("TarRlteTarService1", "hubTarancelList1", {"baseYm": "202504", "numOfRows": 1, "pageNo": 1}),
        ("TarRlteTarService1", "areaBasedList1",   {"baseYm": "202504", "numOfRows": 1, "pageNo": 1}),
        ("HubTarService1",     "areaBasedList1",   {"baseYm": "202504", "numOfRows": 1, "pageNo": 1}),
        ("CenterTarService1",  "areaBasedList1",   {"baseYm": "202504", "numOfRows": 1, "pageNo": 1}),
        ("TarRlteTarService",  "areaBasedList",    {"baseYm": "202504", "numOfRows": 1, "pageNo": 1}),
    ],
    "audio (C-7 관광지 오디오 가이드)": [
        ("AudioGuideService",    "areaBasedList",  {"numOfRows": 1, "pageNo": 1}),
        ("AudioGuideService1",   "areaBasedList1", {"numOfRows": 1, "pageNo": 1}),
        ("KorAudioService",      "areaBasedList",  {"numOfRows": 1, "pageNo": 1}),
        ("OdiiService",          "areaBasedList",  {"numOfRows": 1, "pageNo": 1}),
        ("AudioGuide",           "areaBasedList",  {"numOfRows": 1, "pageNo": 1}),
        ("themeBasedAudioGuide", "areaBasedList",  {"numOfRows": 1, "pageNo": 1}),
    ],
    "visitor (C-1 지역별 방문자수)": [
        ("DataLabService",  "metcoRegnVisitrDDList", {"startYmd": "20250401", "endYmd": "20250430", "numOfRows": 1, "pageNo": 1}),
        ("DataLabService",  "locgoRegnVisitrDDList", {"startYmd": "20250401", "endYmd": "20250430", "numOfRows": 1, "pageNo": 1}),
        ("DataLabService1", "metcoRegnVisitrDDList", {"startYmd": "20250401", "endYmd": "20250430", "numOfRows": 1, "pageNo": 1}),
        ("BigDataService",  "metcoRegnVisitrDDList", {"startYmd": "20250401", "endYmd": "20250430", "numOfRows": 1, "pageNo": 1}),
        ("DataLabService",  "areaBasedList",         {"numOfRows": 1, "pageNo": 1}),
    ],
    "durunubi (C-8 두루누비)": [
        ("Durunubi",  "courseList", {"numOfRows": 1, "pageNo": 1}),
        ("Durunubi",  "routeList",  {"numOfRows": 1, "pageNo": 1}),
        ("Durunubi1", "courseList", {"numOfRows": 1, "pageNo": 1}),
    ],
    "rlte (C-4 연관 관광지 · 확정분 재확인)": [
        ("TarRlteTarService1", "areaBasedList1", {"baseYm": "202504", "numOfRows": 1, "pageNo": 1}),
    ],
}


def probe():
    print("=" * 74)
    print("오퍼레이션 탐침 — resultCode=0000 이 뜨는 조합을 찾습니다")
    print("=" * 74)
    found = {}
    for group, cands in PROBES.items():
        print("\n[%s]" % group)
        hit = None
        for svc, op, p in cands:
            ok, res = call(svc, op, p)
            mark = "  OK  " if ok else "  --  "
            detail = ""
            if ok:
                arr = items_of(res)
                detail = "totalCount=%s  keys=%s" % (
                    res.get("totalCount", "?"),
                    list(arr[0].keys())[:8] if arr else "(빈 응답)")
                if hit is None:
                    hit = (svc, op)
            else:
                detail = str(res)[:90]
            print("%s %-22s %-24s %s" % (mark, svc, op, detail))
            if ok:
                break
            time.sleep(0.3)
        if hit:
            found[group.split()[0]] = {"service": hit[0], "operation": hit[1]}
        else:
            print("       → 후보 전부 실패. 명세 zip(TourAPI_Guide_*)에서 확인 필요")
    out = os.path.join(HERE, "datalab_endpoints.json")
    json.dump(found, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("\n호출 %d회 사용. 확정분 저장 → %s" % (CALLS, out))
    if found:
        print("\n확정된 조합:")
        for k, v in found.items():
            print("  %-10s %s/%s" % (k, v["service"], v["operation"]))
    return found


# ─────────────────────────────────────────────────────────────
# 2. 89곳 로드
# ─────────────────────────────────────────────────────────────
def load89():
    p = os.path.join(RAW, "malgil_89_join.csv")
    rows = {}
    with io.open(p, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            code5 = r["행정표준코드5"]
            rows[code5] = {
                "code5": code5, "sido": r["시도"], "sgg": r["시군구"],
                "regn": code5[:2], "signgu": code5[2:],
                "kor": int(r["국문관광정보"]), "eng": int(r["영문관광정보"]),
            }
    return rows


def endpoints():
    p = os.path.join(HERE, "datalab_endpoints.json")
    if not os.path.exists(p):
        raise SystemExit("datalab_endpoints.json 없음 — 먼저 `python pull_datalab.py probe` 를 실행하세요")
    return json.load(open(p, encoding="utf-8"))


def save(name, obj):
    p = os.path.join(HERE, name)
    json.dump(obj, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("저장 → %s (%d항목)" % (p, len(obj)))


# ─────────────────────────────────────────────────────────────
# 3. pull
# ─────────────────────────────────────────────────────────────
def pull_center(ep, regions, base_ym="202504"):
    """C-5 지자체별 중심 관광지 100위. 89곳 × 1회 = 89 호출."""
    out = {}
    for i, (code5, r) in enumerate(sorted(regions.items()), 1):
        ok, body = call(ep["service"], ep["operation"], {
            "baseYm": base_ym, "areaCd": r["regn"], "signguCd": code5,
            "numOfRows": 100, "pageNo": 1})
        arr = items_of(body) if ok else []
        out[code5] = {"sido": r["sido"], "sgg": r["sgg"], "baseYm": base_ym,
                      "n": len(arr), "items": arr,
                      "error": None if ok else str(body)}
        print("  %3d/89 %-6s %-8s → %s" % (i, r["sido"][:4], r["sgg"],
              ("%d건" % len(arr)) if ok else "실패 %s" % str(body)[:50]))
        time.sleep(0.15)
    save("c5_center_tourspot_89.json", out)


def pull_audio(ep, regions):
    """C-7 오디오 가이드 — 전량 받아서 89곳으로 필터. 페이지 순회."""
    all_items, page = [], 1
    while True:
        ok, body = call(ep["service"], ep["operation"], {"numOfRows": 1000, "pageNo": page})
        if not ok:
            print("  page %d 실패: %s" % (page, body)); break
        arr = items_of(body)
        all_items.extend(arr)
        total = int(body.get("totalCount", 0) or 0)
        print("  page %d → 누적 %d / %d" % (page, len(all_items), total))
        if len(all_items) >= total or not arr:
            break
        page += 1
        time.sleep(0.15)
    save("c7_audioguide_all.json", all_items)
    # 89곳 필터: lDong 5자리가 있으면 그걸로, 없으면 주소 문자열 매칭
    idx = {r["sgg"]: c for c, r in regions.items()}
    hit = collections.defaultdict(list)
    for it in all_items:
        code5 = (it.get("lDongRegnCd") or "") + (it.get("lDongSignguCd") or "")
        if code5 in regions:
            hit[code5].append(it); continue
        addr = (it.get("addr1") or "") + " " + (it.get("title") or "")
        for sgg, c in idx.items():
            if sgg and sgg in addr:
                hit[c].append(it); break
    res = {c: {"sido": regions[c]["sido"], "sgg": regions[c]["sgg"],
               "n": len(v), "titles": [x.get("title", "") for x in v]}
           for c, v in hit.items()}
    save("c7_audioguide_89.json", res)
    print("\n  89곳 중 오디오 가이드 보유 지역: %d곳 / 총 %d건"
          % (len(res), sum(v["n"] for v in res.values())))


def pull_visitor(ep, regions, ymds=("20250401", "20250430")):
    """C-1 방문자수. ⛔ 추세 분석 전용 — 총량 사용 금지(P-DL01)."""
    out = {}
    for i, (code5, r) in enumerate(sorted(regions.items()), 1):
        ok, body = call(ep["service"], ep["operation"], {
            "startYmd": ymds[0], "endYmd": ymds[1],
            "areaCd": r["regn"], "signguCd": code5,
            "numOfRows": 1000, "pageNo": 1})
        arr = items_of(body) if ok else []
        out[code5] = {"sido": r["sido"], "sgg": r["sgg"],
                      "period": "%s~%s" % ymds, "n": len(arr), "items": arr,
                      "error": None if ok else str(body)}
        print("  %3d/89 %-6s %-8s → %s" % (i, r["sido"][:4], r["sgg"],
              ("%d행" % len(arr)) if ok else "실패 %s" % str(body)[:50]))
        time.sleep(0.15)
    save("c1_visitor_89.json", out)
    print("\n  ⚠️ P-DL01 — 이 값은 추세로만 씁니다. 총량으로 인용 금지")


def pull_rlte(ep, regions, base_ym="202504"):
    """C-4 연관 관광지. ⚠️ Tmap 차량 기준 — 소요시간·이동수단 사용 금지(P-DL04)."""
    out = {}
    for i, (code5, r) in enumerate(sorted(regions.items()), 1):
        ok, body = call(ep["service"], ep["operation"], {
            "baseYm": base_ym, "areaCd": r["regn"], "signguCd": code5,
            "numOfRows": 100, "pageNo": 1})
        arr = items_of(body) if ok else []
        out[code5] = {"sido": r["sido"], "sgg": r["sgg"], "baseYm": base_ym,
                      "n": len(arr), "items": arr, "error": None if ok else str(body)}
        print("  %3d/89 %-6s %-8s → %d건" % (i, r["sido"][:4], r["sgg"], len(arr)))
        time.sleep(0.15)
    save("c4_rlte_89.json", out)


def pull_durunubi(ep, regions):
    """C-8 두루누비 코스 전량 (284코스). GPX는 별도 필드."""
    all_items, page = [], 1
    while True:
        ok, body = call(ep["service"], ep["operation"], {"numOfRows": 500, "pageNo": page})
        if not ok:
            print("  page %d 실패: %s" % (page, body)); break
        arr = items_of(body)
        all_items.extend(arr)
        total = int(body.get("totalCount", 0) or 0)
        print("  page %d → 누적 %d / %d" % (page, len(all_items), total))
        if len(all_items) >= total or not arr:
            break
        page += 1
        time.sleep(0.15)
    save("c8_durunubi_courses.json", all_items)
    print("\n  ⚠️ 89곳 통과 구간은 GPX 좌표 × 경계 대조로 별도 산출 (계획서 U-8)")


PULLERS = {"center": pull_center, "audio": pull_audio, "visitor": pull_visitor,
           "rlte": pull_rlte, "durunubi": pull_durunubi}


def main():
    if not KEY:
        raise SystemExit(
            "TOUR_API_KEY 가 설정되지 않았습니다.\n"
            "  PowerShell : $env:TOUR_API_KEY = \"디코딩된키\"\n"
            "  bash       : export TOUR_API_KEY=\"디코딩된키\"\n"
            "그리고 data.go.kr 에서 해당 데이터셋 활용신청이 승인되어 있어야 합니다 (계획서 P0-1).")
    mode = sys.argv[1] if len(sys.argv) > 1 else "probe"
    if mode == "probe":
        probe(); return
    if mode != "pull" or len(sys.argv) < 3:
        raise SystemExit(__doc__)
    what = sys.argv[2]
    if what not in PULLERS:
        raise SystemExit("알 수 없는 대상: %s (%s 중 하나)" % (what, ", ".join(PULLERS)))
    ep_all = endpoints()
    if what not in ep_all:
        raise SystemExit("%s 의 엔드포인트가 아직 확정되지 않았습니다 — probe 를 다시 돌리거나 "
                         "datalab_endpoints.json 에 직접 적어 주세요" % what)
    regions = load89()
    print("89곳 로드 완료. %s pull 시작 (%s/%s)"
          % (what, ep_all[what]["service"], ep_all[what]["operation"]))
    PULLERS[what](ep_all[what], regions)
    print("\n총 %d회 호출 사용 (예산 %d)" % (CALLS, CALL_BUDGET))


if __name__ == "__main__":
    main()
