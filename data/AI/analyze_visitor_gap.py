# -*- coding: utf-8 -*-
"""
말길 · 「내국인은 오는데 외국인은 안 오는 곳」 분석 — 기초지자체별 외국인 방문 비중
  입력  _raw/c1_visitor_raw.json   pull_visitor.py · 2025-08~2026-07 12개월 · 291,345행 (pull 2026-09-07)
        _raw/ldong_269.json        pull_ldong.py · 공사 ldongCode2 시군구 269 (2026-09-14 실측) ← 기초지자체 집합의 기준
        _raw/code_bridge.json      구코드 → 신코드 대응표 (매핑 27쌍 · 인천 그룹 2묶음)
        _raw/malgil_89_join.csv    행안부 인구감소지역 89곳
        ../인간/analyze_89_culture.json (선택 · 콘솔 표시용 문화관광 두께)
  출력  ../인간/analyze_visitor_gap.json  {_설명, 데이터:[기초지자체 행]}
  실행  python data/AI/analyze_visitor_gap.py

  ★ 구분 코드가 이 분석의 전부다
      1 현지인(a) = 그 지역 거주자 → 방문자가 아니므로 제외
      2 외지인(b) = 타지에서 온 내국인 방문자   ← 「내국인이 온다」
      3 외국인(c) = 외국인 방문자               ← 「외국인이 온다」

  ★ 기초지자체 집합 (2026-09-14 확정)
      ldong_269.json 의 269 시군구에서 일반구(수원시 장안구 41111 등 39곳)를 시로 접은 230곳.
      원장에는 시 행(41110)과 그 일반구 행(41111~)이 **둘 다** 있고 시 행 ≈ 일반구 합이라,
      더하면 같은 방문을 두 번 센다 → 일반구 행은 버리고 시 행만 쓴다 (화성시 분구 41591/3/5/7 포함).

  ★ 행정구역 개편 보정
      2026-07 광주(29xxx)+전남(46xxx) → 전남광주통합특별시(12xxx): 구역이 그대로라 구→신 코드로 이어 붙인다 (매핑 27쌍).
      2026-07 인천 중구+동구 → 제물포구+영종구 / 서구 → 서해구+검단구: 구역이 1:1이 아니라 이어 붙일 수 없다.
        · 신코드 행이 있는 달(202607)의 구코드 행은 중복 → 제거
        · 신설 4구 행은 개편 후 1개월치만 있다(months=1). 묶음 합산 비중을 그룹참고share 로만 싣는다
        · 구코드(28110·28140·28260)는 산출물에 남기지 않는다

  ⛔ P-DL01 총량 사용 금지 → 절대 인원수(b·c)는 산출물에 싣지 않는다. 구성비(share) · 백분위 · 순위만
  ⛔ P-DL02 기초 ↔ 광역 합산 금지 → 기초지자체끼리만 비교
  ⛔ P-DL03 「방문자」 ≠ 「관광객」
"""
import io, os, sys, json, csv, bisect, collections, datetime

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
WEEK = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"]
생성일 = datetime.date.today().isoformat()


def load():
    raw = json.load(open(os.path.join(RAW, "c1_visitor_raw.json"), encoding="utf-8"))
    ld = json.load(open(os.path.join(RAW, "ldong_269.json"), encoding="utf-8"))
    br = json.load(open(os.path.join(RAW, "code_bridge.json"), encoding="utf-8"))
    if "매핑" in br:
        매핑, 그룹 = br["매핑"], br.get("그룹", [])
    else:                                   # 구형(평면 dict) 하위호환
        매핑, 그룹 = br, []
    r89 = {}
    with io.open(os.path.join(RAW, "malgil_89_join.csv"), encoding="utf-8-sig") as f:
        for r in csv.DictReader(l for l in f if not l.startswith("#")):
            r89[r["행정표준코드5"]] = {"sido": r["시도"], "sgg": r["시군구"]}
    cul = {}
    p = os.path.join(OUT, "analyze_89_culture.json")
    if os.path.exists(p):
        _raw = json.load(open(p, encoding="utf-8"))
        data = _raw["데이터"] if isinstance(_raw, dict) and "데이터" in _raw else _raw
        rows = data["문화두께"] if isinstance(data, dict) else data
        for x in rows:
            cul[x["code"]] = x
    return raw, ld, 매핑, 그룹, r89, cul


def aggregate(raw, ld, 매핑, 그룹):
    """원장 → 기초지자체(230) 단위 집계.

    반환 tot[code] = {b, c, months, wk{요일:[b,c]}} · 참고[신코드] = 묶음 합산 share · 통계(dict)
    """
    parent = {x["code5"]: x["parent"] for x in ld["시군구"]}
    base = set(parent.values())
    그룹의구 = {c: g for g in 그룹 for c in g["구"]}

    # 1차: (코드, 월) 단위로 모은다. 코드는 매핑(광주·전남)만 먼저 적용
    cell = collections.defaultdict(lambda: [0.0, 0.0])       # (code, ym) → [b, c]
    wk = collections.defaultdict(lambda: collections.defaultdict(lambda: [0.0, 0.0]))
    nrow = collections.Counter()                              # 코드별 행수 (중복 제거 건수 계산용)
    detail = collections.defaultdict(list)                    # 인천 구코드 (code, ym) → [(구분, 일자)]
    for x in raw["items"]:
        div = x.get("touDivCd", "")
        if div == "1":
            continue
        code = 매핑.get(x["signguCode"], x["signguCode"])
        try:
            n = float(x.get("touNum") or 0)
        except ValueError:
            continue
        i = 0 if div == "2" else 1
        ym = x["baseYmd"][:6]
        cell[(code, ym)][i] += n
        wk[code][x.get("daywkDivNm", "")][i] += n
        nrow[(code, ym)] += 1
        if code in 그룹의구:
            detail[(code, ym)].append((div, x["baseYmd"]))

    # 2차: 인천 그룹 — 신코드 행이 있는 달의 구코드 셀 제거
    dup, dup상세 = 0, []
    for g in 그룹:
        신월 = {ym for (c, ym) in cell if c in g["신"]}
        for c in g["구"]:
            for ym in 신월:
                if (c, ym) in cell:
                    dup += nrow.pop((c, ym), 0)
                    d = detail.get((c, ym), [])
                    dup상세.append("%s %s %d행 (구분 %s · %s~%s)" % (
                        c, ym, len(d), "·".join(sorted({v for v, _ in d})),
                        min(x for _, x in d), max(x for _, x in d)))
                    del cell[(c, ym)]
        g["_신월"] = sorted(신월)

    # 3차: 코드별 합계 (일반구 행은 버린다 — 시 행이 따로 있다)
    tot = {}
    버린일반구 = collections.Counter()
    for (c, ym), (b, cc) in cell.items():
        if c in parent and parent[c] != c:
            버린일반구[c] += 1
            continue
        t = tot.setdefault(c, {"b": 0.0, "c": 0.0, "months": set()})
        t["b"] += b; t["c"] += cc; t["months"].add(ym)

    # 4차: 그룹참고share — 구코드(중복 제거 후) + 신코드 전부 합산
    참고 = {}
    for g in 그룹:
        b = sum(t["b"] for c, t in tot.items() if c in g["구"] or c in g["신"])
        cc = sum(t["c"] for c, t in tot.items() if c in g["구"] or c in g["신"])
        g["_share"] = cc / (b + cc) * 100 if (b + cc) else None
        for c in g["신"]:
            참고[c] = g["_share"]

    구코드잔존 = sorted(c for c in tot if c not in base)
    통계 = {"base": len(base), "n_gu": ld.get("n_gu", len(parent) - len(base)),
            "dup_rows": dup, "dup상세": dup상세, "일반구행": len(버린일반구), "구코드제외": 구코드잔존,
            "wk": wk}
    return tot, 참고, base, 통계


def pctr(vals):
    s = sorted(vals)
    return lambda v: bisect.bisect_left(s, v) / max(len(s) - 1, 1) * 100


def med(v):
    v = sorted(v); n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2


def weekend_index(d):
    """주말지수 = 주말 일평균 / 평일 일평균. 관광 수요면 1보다 크다."""
    wd = sum(d[w][0] for w in WEEK[:5]) / 5, sum(d[w][1] for w in WEEK[:5]) / 5
    we = sum(d[w][0] for w in WEEK[5:]) / 2, sum(d[w][1] for w in WEEK[5:]) / 2
    return (we[0] / wd[0] if wd[0] else 0), (we[1] / wd[1] if wd[1] else 0)


def main():
    raw, ld, 매핑, 그룹, r89, cul = load()
    tot, 참고, base, 통계 = aggregate(raw, ld, 매핑, 그룹)
    nm = {x["code5"]: x["nm"] for x in ld["시군구"]}
    sido = {x["code5"]: x["sido"] for x in ld["시군구"]}
    wk = 통계["wk"]

    print("=" * 78)
    print("「내국인은 오는데 외국인은 안 오는 곳」 · %s" % raw["window"])
    print("자료: 한국관광공사_빅데이터_지역별 방문자수 (KT 내국인 / SKT 외국인)")
    print("      DataLabService/locgoRegnVisitrDDList · pull %s · %s행" % (raw.get("pulled_at", "?"), format(raw["n"], ",")))
    print("기초지자체 집합: ldongCode2 %d → 일반구 %d 접음 → %d곳 (원장에 잡힌 곳 %d)"
          % (ld["n_sgg"], 통계["n_gu"], 통계["base"], sum(1 for c in tot if c in base)))
    print("보정: 광주·전남 구→신 매핑 %d쌍 · 인천 중복월 제거 %d행 · 일반구 코드 %d개 행 버림(시 행만 사용) · 산출물 미수록 구코드 %s"
          % (len(매핑), 통계["dup_rows"], 통계["일반구행"], 통계["구코드제외"]))
    for g in 그룹:
        print("  그룹 %s: 신코드 등장월 %s · 묶음 share %.3f%%" % (g["이름"], g["_신월"], g["_share"] or 0))
    for s in 통계["dup상세"]:
        print("  중복 제거: %s" % s)
    print("=" * 78)

    rows = []
    for code in sorted(base):
        if code not in tot:
            continue
        a = tot[code]
        s = a["b"] + a["c"]
        if s <= 0:
            continue
        wb, wc = weekend_index(wk[code])
        rows.append({"code": code, "sido": sido.get(code, "?"), "nm": nm.get(code, "?"),
                     "share": a["c"] / s * 100, "months": len(a["months"]),
                     "is89": code in r89,
                     "그룹참고share": round(참고[code], 3) if code in 참고 and 참고[code] is not None else None,
                     "주말지수_내국인": round(wb, 2), "주말지수_외국인": round(wc, 2),
                     "_b": a["b"]})
    full = [r for r in rows if r["months"] >= 12]
    pb, ps = pctr([r["_b"] for r in full]), pctr([r["share"] for r in full])
    rank_b = {r["code"]: i for i, r in enumerate(sorted(full, key=lambda r: -r["_b"]), 1)}
    for r in rows:
        if r["months"] >= 12:
            r["pb"], r["ps"] = round(pb(r["_b"]), 1), round(ps(r["share"]), 1)
            r["gap"] = round(r["pb"] - r["ps"], 1)
            r["rank_b"] = rank_b[r["code"]]
        else:
            r["pb"] = r["ps"] = r["gap"] = r["rank_b"] = None
        r["share"] = round(r["share"], 3)
        del r["_b"]
    in89 = [r for r in full if r["is89"]]
    out89 = [r for r in full if not r["is89"]]

    print("\n[0] ★ 「인구감소지역에 외국인이 안 온다」는 사실인가 (완전월 12개월 행만)")
    print("    89곳    n=%3d   외국인 비중 중앙값 %5.2f%%" % (len(in89), med([r["share"] for r in in89])))
    print("    비89곳  n=%3d   외국인 비중 중앙값 %5.2f%%" % (len(out89), med([r["share"] for r in out89])))
    d = med([r["share"] for r in in89]) - med([r["share"] for r in out89])
    print("    → 차이 %+.2f%%p — %s" % (
        d, "89곳이 오히려 높음. 「인구감소지역=외국인 안 옴」은 성립하지 않는다" if d > 0 else "89곳이 낮음"))

    print("\n[1] 89곳 중 외국인 비중이 낮은 15곳")
    print("    %-3s %-17s %9s %9s %9s %7s" % ("", "지역", "외국인비중", "외국인%ile", "내국인%ile", "문화관광"))
    for i, r in enumerate(sorted(in89, key=lambda r: r["share"])[:15], 1):
        m = r89[r["code"]]
        print("    %-3d %-17s %8.2f%% %9.1f %9.1f %7s"
              % (i, m["sido"][:5] + " " + m["sgg"], r["share"], r["ps"], r["pb"],
                 cul.get(r["code"], {}).get("culture", "-")))

    print("\n[2] 대조군 · 89곳인데 외국인 비중 상위 5 — 해석 주의 구간")
    for r in sorted(in89, key=lambda x: -x["share"])[:5]:
        m = r89[r["code"]]
        print("    %-17s 외국인 비중 %6.2f%% (%%ile %5.1f)  주말지수 내국인 %.2f / 외국인 %.2f"
              % (m["sido"][:5] + " " + m["sgg"], r["share"], r["ps"], r["주말지수_내국인"], r["주말지수_외국인"]))
    print("    ※ 주말지수 = 주말 일평균 / 평일 일평균. 관광 수요면 1보다 크다.")

    print("\n[3] 인천 신설 4구 (개편 후 1개월 · 판정 보류)")
    for r in rows:
        if r["months"] < 12:
            print("    %s %-5s months=%d share=%.3f%% 그룹참고share=%s" % (r["code"], r["nm"], r["months"], r["share"], r["그룹참고share"]))

    # ── 산출물 ──────────────────────────────────────────────
    out = os.path.join(OUT, "analyze_visitor_gap.json")
    _rows = sorted(rows, key=lambda r: (r["months"] < 12, r["share"]))
    _r0 = _rows[0]
    _ic = next(r for r in _rows if r["months"] < 12)
    _top = min(full, key=lambda r: r["rank_b"])
    _doc = {
        "파일": "analyze_visitor_gap.json",
        "무엇": "「내국인은 오는데 외국인은 안 오는 곳」 — 기초지자체별 외국인 방문 비중과 백분위 격차",
        "생성일": 생성일,
        "생성": "python data/AI/analyze_visitor_gap.py",
        "입력": "AI/_raw/c1_visitor_raw.json (2025-08~2026-07 12개월 · %s행 · pull %s) · AI/_raw/ldong_269.json (ldongCode2 %s 실측 · 시군구 %d) · AI/_raw/code_bridge.json (매핑 %d쌍 · 그룹 %d) · AI/_raw/malgil_89_join.csv" % (
            format(raw["n"], ","), raw.get("pulled_at", "?"), ld.get("pulled_at", "?"), ld["n_sgg"], len(매핑), len(그룹)),
        "정렬": "완전월(12개월) 행을 share 오름차순 → 개편 후 1개월 행(인천 신설 4구)은 맨 뒤",
        "행수": len(_rows),
        "기초지자체집합": "ldongCode2 시군구 %d에서 일반구 %d곳을 시로 접은 %d곳. 원장에는 시 행과 일반구 행이 둘 다 있고 시 행 ≈ 일반구 합이라 더하면 이중 계상 → 일반구 행은 버리고 시 행만 썼다" % (
            ld["n_sgg"], 통계["n_gu"], 통계["base"]),
        "개편보정": {
            "광주·전남": "구코드(29xxx·46xxx) 27쌍을 신코드(12xxx)로 바꿔 12개월을 이어 붙였다",
            "인천": "신코드 행이 있는 달(%s)의 구코드 행 %d행을 중복으로 제거 [%s]. 신설 4구는 months=1 로 남기고 묶음 합산 비중을 그룹참고share 에 실었다. 구코드 28110·28140·28260 은 산출물에 없다" % (
                "·".join(sorted({m for g in 그룹 for m in g["_신월"]})), 통계["dup_rows"], " / ".join(통계["dup상세"]) or "-"),
            "인천_실측메모": "제거된 구코드 행은 서구 28260 의 외국인(구분 3) 7/1~7/5 뿐이고 서해구 28275 외국인 행은 7/6부터 시작한다 — 엄밀히는 중복이 아니라 코드가 바뀐 이어짐이다. 규칙(신코드 등장월의 구코드 행 제거)을 그대로 적용했고 영향은 묶음 참고값 5일치에 그친다",
        },
        "주의": [
            "⛔ P-DL01 총량 사용 금지 — 절대 인원수(b·c)는 이 산출물에 싣지 않았다. 해석은 구성비(share) · 백분위(pb·ps) · 순위(rank_b)로만 한다",
            "P-DL02 기초 ↔ 광역 합산 금지 — 기초지자체끼리만 비교",
            "P-DL03 「방문자」는 「관광객」이 아니다 — 통근·업무 방문이 섞여 있다",
            "백분위·순위는 완전월(months=12) %d행 위에서 계산했다. 개편 후 1개월 행(인천 4구)은 pb·ps·gap·rank_b 가 null" % len(full),
        ],
        "항목": {
            "code": {"뜻": "행정표준코드 5자리 (공사 ldongCode2 기준 신코드)", "산식": "원자료(구코드→신코드 병합)",
                     "범위": "5자리 숫자 문자열", "단위": "코드",
                     "예시": "%s = %s %s" % (_r0["code"], _r0["sido"], _r0["nm"])},
            "sido": {"뜻": "시도명 (ldongCode2 기준)", "산식": "원자료", "범위": "16개", "단위": "문자열", "예시": _r0["sido"]},
            "nm": {"뜻": "시군구명 (ldongCode2 기준)", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": _r0["nm"]},
            "share": {"뜻": "★ 외국인 비중 — 방문자 중 외국인이 차지하는 몫. 이 분석의 핵심 지표",
                      "산식": "외국인(c) / (외지인(b) + 외국인(c)) × 100 · 집계 개월 누계", "범위": "0~100", "단위": "%",
                      "예시": "%s %s %.3f%% — 방문자 1,000명 중 외국인은 %d명꼴 (완전월 행 중 최저)" % (
                          _r0["sido"][:2], _r0["nm"], _r0["share"], round(_r0["share"] * 10))},
            "months": {"뜻": "집계에 잡힌 개월 수. 12 미만이면 개편으로 신설된 코드", "산식": "원자료 집계",
                       "범위": "1~12", "단위": "개월",
                       "예시": "%s %d개월 · 인천 %s %d개월(2026-07 신설)" % (_r0["nm"], _r0["months"], _ic["nm"], _ic["months"])},
            "is89": {"뜻": "행안부 고시 인구감소지역 89곳인가", "산식": "malgil_89_join.csv 대조",
                     "범위": "true / false", "단위": "불리언", "예시": "%s %s" % (_r0["nm"], _r0["is89"])},
            "그룹참고share": {"뜻": "인천 신설 4구에만 있는 참고값 — 개편 전 구코드(중복월 제거) + 신코드를 한 묶음으로 합산한 외국인 비중. 급수 판정에는 쓰지 않는다",
                          "산식": "묶음 c 합 / (묶음 b 합 + 묶음 c 합) × 100", "범위": "0~100 또는 null", "단위": "%",
                          "예시": "인천 %s %s%% — 묶음 「%s」" % (_ic["nm"], _ic["그룹참고share"],
                                                        next(g["이름"] for g in 그룹 if _ic["code"] in g["신"]))},
            "주말지수_내국인": {"뜻": "내국인(외지인) 주말 일평균 / 평일 일평균. 1보다 뚜렷이 크면 관광 목적 방문이 실재", "산식": "주말 2일 평균 / 평일 5일 평균",
                          "범위": "0 이상", "단위": "배", "예시": "%s %.2f" % (_r0["nm"], _r0["주말지수_내국인"])},
            "주말지수_외국인": {"뜻": "외국인 주말 일평균 / 평일 일평균. 관광지에서도 1.0 근처라 변별력이 약하다 — 1보다 뚜렷이 낮을 때만 신호", "산식": "주말 2일 평균 / 평일 5일 평균",
                          "범위": "0 이상", "단위": "배", "예시": "%s %.2f" % (_r0["nm"], _r0["주말지수_외국인"])},
            "pb": {"뜻": "내국인(외지인) 방문 규모의 백분위 — 클수록 내국인이 많이 오는 곳", "산식": "완전월 행 중 b의 백분위",
                   "범위": "0~100 또는 null", "단위": "백분위",
                   "예시": "%s %.1f" % (_r0["nm"], _r0["pb"])},
            "ps": {"뜻": "외국인 비중의 백분위 — 클수록 외국인 비중이 높은 곳", "산식": "완전월 행 중 share의 백분위",
                   "범위": "0~100 또는 null", "단위": "백분위", "예시": "%s %.1f" % (_r0["nm"], _r0["ps"])},
            "gap": {"뜻": "격차 — 값이 클수록 「내국인은 오는데 외국인은 안 오는 곳」", "산식": "pb − ps",
                    "범위": "-100~100 또는 null", "단위": "백분위 차",
                    "예시": "%s %.1f = %.1f − %.1f" % (_r0["nm"], _r0["gap"], _r0["pb"], _r0["ps"])},
            "rank_b": {"뜻": "내국인(외지인) 방문 규모 순위 — 1이 가장 많이 오는 곳. 절대 인원 대신 쓰는 값", "산식": "완전월 행 %d곳 중 b 내림차순 순위" % len(full),
                       "범위": "1~%d 또는 null" % len(full), "단위": "위",
                       "예시": "%s %s 1위 · %s %d위" % (_top["sido"][:2], _top["nm"], _r0["nm"], _r0["rank_b"])},
        }}
    json.dump({"_설명": _doc, "데이터": _rows}, open(out, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("\n저장 → %s (%d행)" % (out, len(_rows)))
    print("⚠️ 절대 인원수는 산출물에 없습니다 (P-DL01). 구성비 · 백분위 · 순위만 사용.")


if __name__ == "__main__":
    main()
