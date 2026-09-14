# -*- coding: utf-8 -*-
"""
말길 · 인구감소지역 89곳 「문화적 · 관광지로서의 가치」 실측
  입력 : dump.json (KorService2 / EngService2 전량, 2026-09-03 실측)
        malgil_89_join.csv (행안부 고시 89곳 + 인구)
  출력 : 89_culture.json · 89_seed_pre.json · 콘솔 리포트
  근거 : Docs/plan/말길_데이터활용계획_v1.0.md §4 · §5-4 · §7

  실행 : python analyze_89_culture.py

  ⚠️ 이 스크립트는 API 키가 필요 없다. 기존 덤프만 쓴다.
     C층(방문자수 · 중심관광지 · 오디오가이드)은 pull_datalab.py 로 별도 확보.
"""
import json, io, os, sys, csv, re, collections, datetime

TODAY = datetime.date.today().isoformat()

# CLAUDE.md 자기설명 규칙 — 한 스크립트는 인간/<스크립트명>.json 하나만 만든다.
_SEC = {}                       # 섹션명 -> 행 배열
_DOC = {
    "파일": "analyze_89_culture.json",
    "무엇": "인구감소지역 89곳 문화관광 자원 분석 — 두 데이터셋(문화두께 · 예비시드)",
    "생성일": TODAY,
    "생성": "python data/AI/analyze_89_culture.py",
    "입력": "AI/_raw/dump.json (TourAPI 전량 실측 2026-09-03) · AI/_raw/malgil_89_join.csv (행안부 고시 89곳 + 인구)",
    "섹션": {},
}

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물

# 국문 / 영문 콘텐츠타입 — 코드 공간이 다르다 (TSD §4-6, 덤프로 실증)
#   국문 12 관광지 · 14 문화시설 · 15 축제공연행사 · 25 여행코스 · 38 쇼핑 · 39 음식점
#   영문 76 관광지 · 78 문화시설 · 85 축제공연행사 · 79 쇼핑 · 82 음식점
KOR_CULTURE = {"12", "14", "15"}
ENG_CULTURE = {"76", "78", "85"}


# ─── CLAUDE.md「데이터 산출물 자기설명 규칙」 준수 ──────────────
#   산출 JSON은 최상위 객체 {"_설명": ..., "데이터": [...]} 형태로 쓴다.
#   항목마다 뜻·산식·범위·단위·예시(실제값)를 한국어로 남긴다.
def ex(row, fmt, *keys):
    """설명 블록의 「예시」를 실제 1행에서 만들어 준다 (가상값 금지)."""
    return fmt % tuple(row[k] for k in keys)


def save_documented(fname, doc, sections):
    """CLAUDE.md 규칙: data/인간/<스크립트명>.json 으로 _설명 + 데이터 를 쓴다."""
    doc = dict(doc)
    for k, v in sections.items():
        doc["섹션"].setdefault(k, {})["행수"] = len(v)
    os.makedirs(OUT, exist_ok=True)
    json.dump({"_설명": doc, "데이터": sections},
              open(os.path.join(OUT, fname), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)


def load_documented(path):
    """_설명 블록이 있든 없든 행 배열을 돌려준다 (하위호환)."""
    raw = json.load(open(path, encoding="utf-8"))
    return raw["데이터"] if isinstance(raw, dict) and "데이터" in raw else raw


def code5(r):
    a = (r.get("lDongRegnCd") or "") + (r.get("lDongSignguCd") or "")
    return a if len(a) == 5 else None


def load():
    dump = json.load(open(os.path.join(RAW, "dump.json"), encoding="utf-8"))
    regions = {}
    with io.open(os.path.join(RAW, "malgil_89_join.csv"), encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            regions[r["행정표준코드5"]] = {
                "sido": r["시도"], "sgg": r["시군구"],
                "p5074": int(r["50-74세"]),
                "kor": int(r["국문관광정보"]), "eng": int(r["영문관광정보"]),
            }
    return dump, regions


def per_region(dump, regions):
    kor = collections.defaultdict(list)
    eng = collections.defaultdict(list)
    for r in dump["KorService2"]["items"]:
        c = code5(r)
        if c in regions and r.get("contenttypeid") in KOR_CULTURE:
            kor[c].append(r)
    for r in dump["EngService2"]["items"]:
        c = code5(r)
        if c in regions and r.get("contenttypeid") in ENG_CULTURE:
            eng[c].append(r)
    return kor, eng


# ─── 1. 지역별 문화관광 자원 두께 ────────────────────────────
def report_thickness(regions, kor, eng):
    rows = []
    for c, x in regions.items():
        tc = collections.Counter(r["contenttypeid"] for r in kor[c])
        rows.append(dict(code=c, sido=x["sido"], sgg=x["sgg"],
                         culture=len(kor[c]), t12=tc["12"], t14=tc["14"], t15=tc["15"],
                         eng_cul=len(eng[c]), p5074=x["p5074"]))
    rows.sort(key=lambda r: -r["culture"])
    print("=" * 62)
    print("1. 인구감소지역 89곳 · 문화관광 자원 두께 (국문 관광지+문화시설+축제)")
    print("=" * 62)
    print("%2s  %-18s%7s%6s%7s%5s%6s" % ("순", "지역", "문화관광", "관광지", "문화시설", "축제", "영문"))
    for i, r in enumerate(rows[:15], 1):
        print("%2d  %-18s%7d%6d%7d%5d%6d" % (
            i, r["sido"][:5] + " " + r["sgg"], r["culture"], r["t12"], r["t14"], r["t15"], r["eng_cul"]))
    tot_k = sum(r["culture"] for r in rows)
    tot_e = sum(r["eng_cul"] for r in rows)
    print("\n  89곳 합계 — 국문 %s건 / 영문 %s건 (커버율 %.1f%%)" % (
        format(tot_k, ","), format(tot_e, ","), tot_e / tot_k * 100))
    _SEC["문화두께"] = rows
    _DOC["섹션"]["문화두께"] = {
        "무엇": "인구감소지역 89곳의 문화관광 자원 두께 — 국문/영문 카탈로그 등재 건수를 유형별로 분해한 사실 기록",
        "정렬": "culture 내림차순 (문화 자원이 두꺼운 순)",
        "주의": "등재 언어를 세는 것이지 현장에서 쓰는 언어가 아님 (기획서 §2-8 주장 범위 선언)",
        "항목": {
            "code": {"뜻": "행정표준코드 5자리", "산식": "원자료", "범위": "5자리 숫자 문자열", "단위": "코드",
                     "예시": ex(rows[0], "%s = %s %s", "code", "sido", "sgg")},
            "sido": {"뜻": "시도명", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": ex(rows[0], "%s", "sido")},
            "sgg": {"뜻": "시군구명", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": ex(rows[0], "%s", "sgg")},
            "culture": {"뜻": "국문 문화관광 콘텐츠 합계 (음식점·쇼핑 제외)", "산식": "t12 + t14 + t15",
                        "범위": "%d~%d건" % (min(r["culture"] for r in rows), max(r["culture"] for r in rows)),
                        "단위": "건",
                        "예시": ex(rows[0], "%s %s건 = 관광지 %s + 문화시설 %s + 축제 %s (89곳 중 최다)",
                                 "sgg", "culture", "t12", "t14", "t15")},
            "t12": {"뜻": "관광지 (국문 contenttypeid=12)", "산식": "원자료 집계", "범위": "0 이상", "단위": "건",
                    "예시": ex(rows[0], "%s %s건", "sgg", "t12")},
            "t14": {"뜻": "문화시설 (국문 contenttypeid=14)", "산식": "원자료 집계", "범위": "0 이상", "단위": "건",
                    "예시": ex(rows[0], "%s %s건", "sgg", "t14")},
            "t15": {"뜻": "축제공연행사 (국문 contenttypeid=15)", "산식": "원자료 집계", "범위": "0 이상", "단위": "건",
                    "예시": ex(rows[0], "%s %s건", "sgg", "t15")},
            "eng_cul": {"뜻": "같은 3유형의 영문 카탈로그 등재 건수 (영문 76·78·85)", "산식": "원자료 집계",
                        "범위": "0 이상 · culture 이하", "단위": "건",
                        "예시": ex(rows[0], "%s %s건 — 국문 %s건 중 영문은 이만큼뿐", "sgg", "eng_cul", "culture")
                                + " · 89곳 합계 국문 %s / 영문 %s (커버율 %.1f%%)" % (
                                    format(tot_k, ","), format(tot_e, ","), tot_e / tot_k * 100)},
            "p5074": {"뜻": "50~74세 인구 — 동네 말벗 공급 모수 (기획서 §2-5)",
                      "산식": "원자료 (주민등록 2026년 8월)", "범위": "0 이상", "단위": "명",
                      "예시": ex(rows[0], "%s %s명", "sgg", "p5074")},
        }}
    return rows, tot_k, tot_e


# ─── 2. 유형별 영문 커버율 — 무엇이 한국어로만 열려 있나 ──────
# 1글자 키워드(사·산·도)는 어미 위치를 고정해 오탐을 막는다.
TYPE_PATTERNS = [
    ("향교",          r"향교",                              r"hyanggyo|confucian school"),
    ("서원",          r"서원",                              r"seowon|confucian academy"),
    ("사찰",          r"(사|암)(\(|\[|$|\s)|사찰|암자",        r"temple|buddhis"),
    ("고택·생가·종택",  r"고택|생가|종택",                      r"\bhouse\b|birthplace|residence|hanok"),
    ("기념관·박물관",   r"기념관|박물관|전시관",                  r"memorial|museum|exhibition"),
    ("축제",          r"축제|제전|문화제",                     r"festival"),
    ("해수욕장·해변",   r"해수욕장|해변",                       r"beach"),
    ("산(山)",        r"(^|\s|·)[가-힣]{1,4}산(\(|\[|$|\s|·)",  r"\bmt\.?\b|mountain|-san\b"),
    ("섬·도(島)",     r"(^|\s)[가-힣]{1,4}도(\(|\[|$|\s)|섬",   r"island|-do\b"),
]


def report_types(dump, regions, base_pct):
    kt = [r["title"] for r in dump["KorService2"]["items"]
          if code5(r) in regions and r.get("contenttypeid") in KOR_CULTURE]
    et = [r["title"] for r in dump["EngService2"]["items"]
          if code5(r) in regions and r.get("contenttypeid") in ENG_CULTURE]
    print("\n" + "=" * 62)
    print("2. 유형별 영문 커버율 — 무엇이 한국어로만 열려 있나")
    print("=" * 62)
    print("%-18s%6s%6s%9s%9s" % ("유형", "국문", "영문", "커버율", "기저대비"))
    out = []
    for lab, kr, en in TYPE_PATTERNS:
        a = sum(1 for t in kt if re.search(kr, t))
        b = sum(1 for t in et if re.search(en, t, re.I))
        cov = (b / a * 100) if a else 0.0
        out.append((lab, a, b, cov, cov / base_pct))
    for lab, a, b, cov, rel in sorted(out, key=lambda x: x[3]):
        flag = "◀ 한국어로만" if rel < 0.5 else ("▶ 영어로 열림" if rel >= 1.2 else "")
        print("%-18s%6d%6d%8.1f%%%8.2fx  %s" % (lab, a, b, cov, rel, flag))
    # 시장은 쇼핑(38/79)으로 분류돼 위 표에 안 잡힌다
    k38 = [r["title"] for r in dump["KorService2"]["items"]
           if code5(r) in regions and r.get("contenttypeid") == "38" and "시장" in r["title"]]
    e79 = [r["title"] for r in dump["EngService2"]["items"]
           if code5(r) in regions and r.get("contenttypeid") == "79"
           and re.search("market", r["title"], re.I)]
    print("\n  참고 · 「시장」은 쇼핑(38)으로 분류됨 — 국문 %d건 / 영문 %d건 (%.1f%%)"
          % (len(k38), len(e79), len(e79) / max(len(k38), 1) * 100))
    print("  ※ 제목 문자열 매칭 근사치. 좌표 매칭이 아니므로 ±오차 있음")
    return out


# ─── 3. 예비 시드 랭킹 (C층 없이) ────────────────────────────
def report_seed(regions, kor, eng):
    cul = {c: len(kor[c]) for c in regions}
    def norm(vals):
        lo, hi = min(vals), max(vals)
        rng = (hi - lo) or 1
        return lambda v: (v - lo) / rng
    nc = norm(list(cul.values()))
    np_ = norm([regions[c]["p5074"] for c in regions])
    rows = []
    for c, x in regions.items():
        lock = 1 - (len(eng[c]) / max(cul[c], 1))
        rows.append(dict(code=c, sido=x["sido"], sgg=x["sgg"], cul=cul[c],
                         engc=len(eng[c]), lock=lock, p5074=x["p5074"],
                         pre=0.45 * nc(cul[c]) + 0.35 * lock + 0.20 * np_(x["p5074"])))
    rows.sort(key=lambda r: -r["pre"])
    print("\n" + "=" * 62)
    print("3. 예비 시드 랭킹 — 두께 0.45 · 잠금 0.35 · 말벗 0.20")
    print("   ⚠️ C층(방문자 · 중심관광지 · 오디오가이드) 미반영. 확보 후 §7 정식 산식으로 재계산")
    print("=" * 62)
    print("%2s  %-18s%7s%6s%9s%10s%8s" % ("순", "지역", "문화관광", "영문", "잠금율", "50-74세", "예비점"))
    for i, r in enumerate(rows[:12], 1):
        print("%2d  %-18s%7d%6d%8.1f%%%10s%8.3f" % (
            i, r["sido"][:5] + " " + r["sgg"], r["cul"], r["engc"],
            r["lock"] * 100, format(r["p5074"], ","), r["pre"]))
    _SEC["예비시드"] = rows
    _DOC["섹션"]["예비시드"] = {
        "무엇": "인구감소지역 89곳의 예비 시드 랭킹 — 시드 말벗을 먼저 심을 지역(=여행 맵에 먼저 넣을 지역) 우선순위",
        "정렬": "pre 내림차순 (우선순위 높은 순)",
        "잠정": "⚠️ 예비 랭킹입니다. C층(방문자수·중심관광지·오디오가이드) 미반영 — 확보 후 정식 산식으로 재계산",
        "가중치근거": "미확정 — 0.45/0.35/0.20의 산정 근거를 Docs/plan/말길_데이터활용계획_v1.0.md에 명시해야 함",
        "항목": {
            "code": {"뜻": "행정표준코드 5자리", "산식": "원자료", "범위": "5자리 숫자 문자열", "단위": "코드",
                     "예시": ex(rows[0], "%s = %s %s", "code", "sido", "sgg")},
            "sido": {"뜻": "시도명", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": ex(rows[0], "%s", "sido")},
            "sgg": {"뜻": "시군구명", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": ex(rows[0], "%s", "sgg")},
            "cul": {"뜻": "국문 문화관광 콘텐츠 합계 (89_culture.json의 culture와 동일)",
                    "산식": "관광지 + 문화시설 + 축제",
                    "범위": "%d~%d건" % (min(r["cul"] for r in rows), max(r["cul"] for r in rows)), "단위": "건",
                    "예시": ex(rows[0], "%s %s건", "sgg", "cul")},
            "engc": {"뜻": "같은 3유형의 영문 등재 건수 (89_culture.json의 eng_cul과 동일)", "산식": "원자료 집계",
                     "범위": "0 이상 · cul 이하", "단위": "건", "예시": ex(rows[0], "%s %s건", "sgg", "engc")},
            "lock": {"뜻": "한국어로만 잠긴 비율 — 국문에는 있는데 영문에는 없는 콘텐츠의 몫",
                     "산식": "1 − engc / cul",
                     "범위": "0~1 (1에 가까울수록 한국어 전용. 0이면 전부 영문으로도 열림)", "단위": "비율",
                     "예시": "%s %.3f — 문화관광 %d건 중 영문은 %d건뿐이라 %.1f%%가 한국어로만 열림" % (
                         rows[0]["sgg"], rows[0]["lock"], rows[0]["cul"], rows[0]["engc"], rows[0]["lock"] * 100)},
            "p5074": {"뜻": "50~74세 인구 — 동네 말벗 공급 모수", "산식": "원자료 (주민등록 2026년 8월)",
                      "범위": "0 이상", "단위": "명", "예시": ex(rows[0], "%s %s명", "sgg", "p5074")},
            "pre": {"뜻": "예비 점수 — 시드 말벗 우선순위. 값이 클수록 먼저 손댈 지역",
                    "산식": "0.45 × 정규화(cul) + 0.35 × lock + 0.20 × 정규화(p5074)"
                            "  ※정규화 = (값−최솟값)/(최댓값−최솟값)",
                    "범위": "0~1 (이론상. 실제 관측 %.3f~%.3f)" % (
                        min(r["pre"] for r in rows), max(r["pre"] for r in rows)), "단위": "점",
                    "예시": "%s %.3f = 89곳 중 1위" % (rows[0]["sgg"], rows[0]["pre"])},
        }}
    return rows


# ─── 4. 특정 지역의 핀 후보 ──────────────────────────────────
def report_pins(rows, kor, eng, names=("영주시", "신안군", "안동시")):
    print("\n" + "=" * 62)
    print("4. 지역별 핀 후보 — 국문에만 있는 것 vs 영문에도 있는 것")
    print("=" * 62)
    by = {r["sgg"]: r for r in rows}
    for nm in names:
        if nm not in by:
            continue
        r = by[nm]
        rank = rows.index(r) + 1
        print("\n★ %s — 예비 %d위 · 문화관광 %d건 · 영문 %d건 · 잠금 %.1f%%"
              % (nm, rank, r["cul"], r["engc"], r["lock"] * 100))
        ts = [x["title"] for x in kor[r["code"]] if x.get("contenttypeid") == "12"][:12]
        et = sorted(set(x["title"].split(" (")[0] for x in eng[r["code"]]))
        print("   국문 관광지: " + " · ".join(ts))
        print("   영문 등재  : " + (" · ".join(et) if et else "(없음)"))


def main():
    dump, regions = load()
    kor, eng = per_region(dump, regions)
    rows, tk, te = report_thickness(regions, kor, eng)
    report_types(dump, regions, te / tk * 100)
    seed = report_seed(regions, kor, eng)
    report_pins(seed, kor, eng)
    save_documented("analyze_89_culture.json", _DOC, _SEC)
    print("\n저장 → data/인간/analyze_89_culture.json (섹션: %s)" % " · ".join(_SEC))


if __name__ == "__main__":
    main()
