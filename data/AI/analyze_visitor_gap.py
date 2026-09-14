# -*- coding: utf-8 -*-
"""
말길 · 「내국인은 오는데 외국인은 안 오는 곳」 분석
  입력  c1_visitor_raw.json (pull_visitor.py, 2025-08~2026-07 12개월 · 291,345행)
        malgil_89_join.csv · 89_culture.json(선택)
  실행  python analyze_visitor_gap.py

  ★ 구분 코드가 이 분석의 전부다
      1 현지인(a) = 그 지역 거주자 → 방문자가 아니므로 제외
      2 외지인(b) = 타지에서 온 내국인 방문자   ← 「내국인이 온다」
      3 외국인(c) = 외국인 방문자               ← 「외국인이 온다」

  ★ 행정구역 개편 보정 (2026-09-07 발견)
      2026-07 광주(29xxx)+전남(46xxx) → 전남광주통합특별시(12xxx)
      보정 없이 집계하면 전남 16곳이 12개월 중 1개월만 잡혀 수치가 완전히 망가진다.
      code_bridge.json 으로 구코드 → 신코드 병합 후 집계한다.
      화성시 분구(41591/3/5/7, 202602~)는 41590과 중복이므로 제외.
      인천 제물포구(28125, 1개월)는 28110+28140의 후신이나 89곳이 아니므로 제외.

  ⛔ P-DL01 총량 사용 금지 → 절대 인원수를 쓰지 않고 구성비 + 백분위로만 표현
  ⛔ P-DL02 기초 ↔ 광역 합산 금지 → 기초지자체끼리만 비교
  ⛔ P-DL03 「방문자」 ≠ 「관광객」
"""
import io, os, sys, json, csv, bisect, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
DROP = {"41591", "41593", "41595", "41597", "28125"}
WEEK = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"]


def load():
    raw = json.load(open(os.path.join(RAW, "c1_visitor_raw.json"), encoding="utf-8"))
    bridge = {}
    p = os.path.join(RAW, "code_bridge.json")
    if os.path.exists(p):
        bridge = json.load(open(p, encoding="utf-8"))
    r89 = {}
    with io.open(os.path.join(RAW, "malgil_89_join.csv"), encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            r89[r["행정표준코드5"]] = {"sido": r["시도"], "sgg": r["시군구"]}
    cul = {}
    p = os.path.join(HERE, "89_culture.json")
    if os.path.exists(p):
        _raw = json.load(open(p, encoding="utf-8"))
        # CLAUDE.md 자기설명 규칙: {"_설명":..., "데이터":[...]} 또는 순수 배열 둘 다 허용
        for x in (_raw["데이터"] if isinstance(_raw, dict) and "데이터" in _raw else _raw):
            cul[x["code"]] = x
    return raw, bridge, r89, cul


def aggregate(raw, bridge):
    tot = collections.defaultdict(lambda: {"nm": "", "b": 0.0, "c": 0.0})
    mon = collections.defaultdict(lambda: collections.defaultdict(lambda: [0.0, 0.0]))
    wk = collections.defaultdict(lambda: collections.defaultdict(lambda: [0.0, 0.0]))
    seen = collections.defaultdict(set)
    for x in raw["items"]:
        div = x.get("touDivCd", "")
        if div == "1":
            continue
        code = bridge.get(x["signguCode"], x["signguCode"])
        if code in DROP:
            continue
        try:
            n = float(x.get("touNum") or 0)
        except ValueError:
            continue
        i = 0 if div == "2" else 1
        ym = x["baseYmd"][:6]
        tot[code]["nm"] = x.get("signguNm", "")
        tot[code]["b" if i == 0 else "c"] += n
        mon[code][ym][i] += n
        wk[code][x.get("daywkDivNm", "")][i] += n
        seen[code].add(ym)
    return tot, mon, wk, seen


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
    raw, bridge, r89, cul = load()
    tot, mon, wk, seen = aggregate(raw, bridge)
    print("=" * 78)
    print("「내국인은 오는데 외국인은 안 오는 곳」 · %s · 기초지자체 %d개"
          % (raw["window"], len(tot)))
    print("자료: 한국관광공사_빅데이터_지역별 방문자수 (KT 내국인 / SKT 외국인)")
    print("      DataLabService/locgoRegnVisitrDDList · pull 2026-09-07 · 291,345행")
    print("      ※ 2026-07 광주·전남 통합 코드개편 보정 적용 (27건 병합)")
    print("=" * 78)

    rows = []
    for code, a in tot.items():
        if len(seen[code]) < 11:
            continue
        s = a["b"] + a["c"]
        if s <= 0:
            continue
        rows.append({"code": code, "nm": a["nm"], "b": a["b"], "c": a["c"],
                     "share": a["c"] / s * 100, "is89": code in r89,
                     "months": len(seen[code])})
    pb, ps = pctr([r["b"] for r in rows]), pctr([r["share"] for r in rows])
    for r in rows:
        r["pb"], r["ps"] = pb(r["b"]), ps(r["share"])
        r["gap"] = r["pb"] - r["ps"]
    in89 = [r for r in rows if r["is89"]]
    out89 = [r for r in rows if not r["is89"]]

    print("\n[0] ★ 「인구감소지역에 외국인이 안 온다」는 사실인가")
    print("    89곳    n=%3d   외국인 비중 중앙값 %5.2f%%" % (len(in89), med([r["share"] for r in in89])))
    print("    비89곳  n=%3d   외국인 비중 중앙값 %5.2f%%" % (len(out89), med([r["share"] for r in out89])))
    d = med([r["share"] for r in in89]) - med([r["share"] for r in out89])
    print("    → 차이 %+.2f%%p — %s" % (
        d, "89곳이 오히려 높음. 「인구감소지역=외국인 안 옴」은 성립하지 않는다"
        if d > 0 else "89곳이 낮음"))

    print("\n[1] 89곳 중 외국인 비중이 낮은 15곳 (내국인 방문 규모 백분위 동반 표기)")
    print("    %-3s %-17s %9s %9s %9s %7s" % ("", "지역", "외국인비중", "외국인%ile", "내국인%ile", "문화관광"))
    low = sorted(in89, key=lambda r: r["share"])[:15]
    for i, r in enumerate(low, 1):
        m = r89[r["code"]]
        print("    %-3d %-17s %8.2f%% %9.1f %9.1f %7s"
              % (i, m["sido"][:5] + " " + m["sgg"], r["share"], r["ps"], r["pb"],
                 cul.get(r["code"], {}).get("culture", "-")))

    print("\n[2] ★ 시드 후보 — 문화관광 자원이 두꺼운데(≥80건) 외국인 비중이 낮은 곳")
    cand = [r for r in in89 if cul.get(r["code"], {}).get("culture", 0) >= 80]
    cand.sort(key=lambda r: r["share"])
    print("    %-3s %-17s %9s %9s %7s %8s %s"
          % ("", "지역", "외국인비중", "외국인%ile", "문화관광", "영문", "주말지수(내/외)"))
    for i, r in enumerate(cand[:12], 1):
        m = r89[r["code"]]; c = cul.get(r["code"], {})
        wb, wc = weekend_index(wk[r["code"]])
        print("    %-3d %-17s %8.2f%% %9.1f %7d %8d   %.2f / %.2f"
              % (i, m["sido"][:5] + " " + m["sgg"], r["share"], r["ps"],
                 c.get("culture", 0), c.get("eng_cul", 0), wb, wc))

    print("\n[3] 대조군 · 89곳인데 외국인 비중 상위 5 — 해석 주의 구간")
    for r in sorted(in89, key=lambda x: -x["share"])[:5]:
        m = r89[r["code"]]
        wb, wc = weekend_index(wk[r["code"]])
        print("    %-17s 외국인 비중 %6.2f%% (%%ile %5.1f)  주말지수 내국인 %.2f / 외국인 %.2f"
              % (m["sido"][:5] + " " + m["sgg"], r["share"], r["ps"], wb, wc))
    print("    ※ 주말지수 = 주말 일평균 / 평일 일평균. 관광 수요면 1보다 크다.")
    print("      외국인 주말지수가 1 미만이면 관광이 아닌 체류(노동·거주)일 가능성 — 해석 주의")

    print("\n[4] 기준점 · 관광지가 확실한 시군구")
    for code, label in (("11110", "서울 종로구"), ("26350", "부산 해운대구"),
                        ("50110", "제주시"), ("51150", "강원 강릉시")):
        if code not in tot:
            continue
        s = tot[code]["b"] + tot[code]["c"]
        wb, wc = weekend_index(wk[code])
        print("    %-14s 외국인 비중 %6.2f%%   주말지수 내국인 %.2f / 외국인 %.2f"
              % (label, tot[code]["c"] / s * 100 if s else 0, wb, wc))

    out = os.path.join(OUT, "analyze_visitor_gap.json")
    _rows = sorted(rows, key=lambda r: r["share"])
    _r0 = _rows[0]
    _doc = {
        "파일": "analyze_visitor_gap.json",
        "무엇": "「내국인은 오는데 외국인은 안 오는 곳」 — 기초지자체별 외국인 방문 비중과 백분위 격차",
        "생성일": __import__("datetime").date.today().isoformat(),
        "생성": "python data/AI/analyze_visitor_gap.py",
        "입력": "AI/_raw/c1_visitor_raw.json (2025-08~2026-07 12개월 · 291,345행) · AI/_raw/malgil_89_join.csv",
        "정렬": "share 오름차순 (외국인 비중이 낮은 곳부터)",
        "행수": len(_rows),
        "주의": [
            "P-DL01 총량 사용 금지 — 해석은 구성비(share)와 백분위(pb·ps)로만 한다",
            "⚠️ 현재 b·c 절대값이 산출물에 남아 있다. 문서 인용 시 절대 인원수를 쓰지 말 것",
            "P-DL02 기초 ↔ 광역 합산 금지 — 기초지자체끼리만 비교",
            "P-DL03 「방문자」는 「관광객」이 아니다",
        ],
        "항목": {
            "code": {"뜻": "행정표준코드 5자리", "산식": "원자료(구코드→신코드 병합)",
                     "범위": "5자리 숫자 문자열", "단위": "코드",
                     "예시": "%s = %s" % (_r0["code"], _r0["nm"])},
            "nm": {"뜻": "시군구명", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": _r0["nm"]},
            "b": {"뜻": "외지인 방문자 지표 12개월 누계 (구분코드 2 — 타지에서 온 내국인)",
                  "산식": "원자료 합계", "범위": "0 이상", "단위": "지표값(절대량)",
                  "예시": "%s %s — ⛔ 이 절대값은 해석·인용에 쓰지 않는다(P-DL01). pb를 쓸 것" % (_r0["nm"], format(int(_r0["b"]), ","))},
            "c": {"뜻": "외국인 방문자 지표 12개월 누계 (구분코드 3)",
                  "산식": "원자료 합계", "범위": "0 이상", "단위": "지표값(절대량)",
                  "예시": "%s %s — ⛔ 절대값 인용 금지(P-DL01)" % (_r0["nm"], format(int(_r0["c"]), ","))},
            "share": {"뜻": "★ 외국인 비중 — 방문자 중 외국인이 차지하는 몫. 이 분석의 핵심 지표",
                      "산식": "c / (b + c) × 100", "범위": "0~100", "단위": "%",
                      "예시": "%s %.2f%% — 방문자 100명 중 외국인은 %.1f명꼴 (89곳 중 최저)" % (
                          _r0["nm"], _r0["share"], _r0["share"])},
            "is89": {"뜻": "행안부 고시 인구감소지역 89곳인가", "산식": "malgil_89_join.csv 대조",
                     "범위": "true / false", "단위": "불리언", "예시": "%s %s" % (_r0["nm"], _r0["is89"])},
            "months": {"뜻": "집계에 잡힌 개월 수. 12 미만이면 행정구역 개편 영향 의심",
                       "산식": "원자료 집계", "범위": "1~12", "단위": "개월",
                       "예시": "%s %d개월" % (_r0["nm"], _r0["months"])},
            "pb": {"뜻": "내국인 방문 규모의 백분위 — 클수록 내국인이 많이 오는 곳",
                   "산식": "전체 기초지자체 중 b의 백분위", "범위": "0~100", "단위": "백분위",
                   "예시": "%s %.1f — 전국 기초지자체 중 상위 %.0f%% 수준으로 내국인이 온다" % (
                       _r0["nm"], _r0["pb"], 100 - _r0["pb"])},
            "ps": {"뜻": "외국인 비중의 백분위 — 클수록 외국인 비중이 높은 곳",
                   "산식": "전체 기초지자체 중 share의 백분위", "범위": "0~100", "단위": "백분위",
                   "예시": "%s %.1f" % (_r0["nm"], _r0["ps"])},
            "gap": {"뜻": "★ 격차 — 값이 클수록 「내국인은 오는데 외국인은 안 오는 곳」",
                    "산식": "pb − ps", "범위": "-100~100", "단위": "백분위 차",
                    "예시": "%s %.1f = 내국인 백분위 %.1f − 외국인비중 백분위 %.1f" % (
                        _r0["nm"], _r0["gap"], _r0["pb"], _r0["ps"])},
        }}
    json.dump({"_설명": _doc, "데이터": _rows}, open(out, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("\n저장 → %s" % out)
    print("⚠️ 절대 인원수는 산출물에 없습니다 (P-DL01). 구성비 · 백분위 · 비율만 사용.")


if __name__ == "__main__":
    main()
