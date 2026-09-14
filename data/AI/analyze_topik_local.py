# -*- coding: utf-8 -*-
"""
말길 · 「TOPIK 급수별로 갈 수 있는 로컬 지역」 판별 — 급수 규칙 v2 (2026-09-14)
  입력  _raw/dump.json                 TourAPI 전량 실측 (dumped_at 필드) · ★ KorService2(국문)만 사용
        _raw/ldong_269.json            공사 ldongCode2 시군구 269 (pull_ldong.py) ← 기초지자체 집합의 기준
        _raw/age_sgg_utf8.csv          주민등록 인구 2026년 8월
        _raw/malgil_89_join.csv        행안부 인구감소지역 89곳
        ../인간/analyze_visitor_gap.json  방문자 구성비·백분위 (기초지자체 230행 · 이미 병합·보정 완료)
  출력  ../인간/analyze_topik_local.json
  실행  python data/AI/analyze_topik_local.py

  ★ 이 분석이 영문 카탈로그를 쓰지 않는 이유 (기획서 P-M04)
      「영문 등재 여부」로 장소의 열림/닫힘을 판정하면, 중국어·일본어·베트남어권
      방문자를 전부 영어권으로 치환하게 된다. 그렇게 만든 지표가 실제로 재는 값은
      「영어 번역 진척도」이지 「한국어가 필요한 정도」가 아니다.
      → 그래서 축을 바꾼다. 카탈로그의 언어가 아니라 **누가 실제로 오는가**로 잰다.
      dump.json 에 EngService2 가 함께 있지만 이 스크립트는 읽지 않는다.

  ★ 급수 규칙 v2 — 상수 4개, 전부 절대값 기준 (백분위 ps 는 더 이상 쓰지 않는다)
      months < 12                      → 보류    인천 2026-07 신설 4구 (방문자 자료 1개월)
      kor < KOR_T(20)                  → 제외    국문 관광자원이 20건 미만 — 맵을 그릴 재료가 없다
      share ≥ SHARE_T(2.0)             → Lv1~2   방문자 50명 중 1명 이상이 외국인 — 다국어 안내가 이미 깔려 있다
      구분 == 자치구 or pb ≥ PB_T(60)  → Lv3     이동·숙박 인프라는 있고 응대 언어만 한국어
      구분 == 군 and e65 ≥ OLD65_T(40) → Lv5     주민 10명 중 4명 이상이 65세 이상인 군 — 말벗이 곧 동네
      나머지                            → Lv4
      구분 = 이름 접미사로만 정한다 (군 / 구=자치구 / 시). 광역 코드 집합은 폐기 —
      군위군·달성군(대구) · 강화군·옹진군(인천) · 기장군(부산) · 울주군(울산)이 자치구로 오분류되던 버그의 원인이었다.
      일반구는 analyze_visitor_gap 단계에서 이미 시로 접혀 있으므로 남은 「구」는 전부 자치구다.

  ⛔ P-DL01 총량 사용 금지 → 방문자는 구성비(share)와 백분위(pb)·순위(rank_b)로만 해석
  ⛔ P-DL02 기초 ↔ 광역 합산 금지
  ⛔ P-DL03 「방문자」 ≠ 「관광객」
"""
import io, os, sys, json, csv, collections, datetime

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물

생성일 = datetime.date.today().isoformat()

# ── 급수 규칙 v2 상수 ──────────────────────────────────────
KOR_T = 20        # 국문 관광자원(관광지+문화시설+축제+음식점) 최소 건수
SHARE_T = 2.0     # 외국인 방문 비중(%) — 50명 중 1명
OLD65_T = 40.0    # 65세 이상 인구 비율(%) — 10명 중 4명
PB_T = 60         # 내국인 방문 규모 백분위 — 시·군인데 내국인 왕래가 많은 곳
LV_ORDER = ["Lv1~2", "Lv3", "Lv4", "Lv5", "제외", "보류"]
사용자급수 = ["Lv1~2", "Lv3", "Lv4", "Lv5"]      # 사용자 급수 → 열린 곳 = 그 급수 이하의 lv 전부

유형 = {"12": "관광지", "14": "문화시설", "15": "축제공연행사", "38": "쇼핑", "39": "음식점"}

# ── 국문 카탈로그 분류체계 (lclsSystm) ─────────────────────────
#   공사 API가 코드만 내려주고 라벨은 주지 않는다. 아래 이름은 89곳 12,447건의
#   title 표본을 직접 읽고 붙인 것이며 공사 공식 명칭이 아니다 (산출물에 명시).
대분류 = {
    "FD": "음식", "HS": "역사", "NA": "자연", "VE": "문화·관광시설",
    "AC": "숙박·야영", "EX": "체험", "LS": "레포츠", "SH": "쇼핑",
    "EV": "축제·공연", "C01": "추천 여행코스",
}
중분류 = {
    "FD01": "한식", "FD02": "양식·중식·일식", "FD03": "분식·간식", "FD04": "주점", "FD05": "카페·제과",
    "HS01": "서원·고택·생가 등 역사유적", "HS02": "비·석불·정려 등 기념물",
    "HS03": "사찰·종교시설", "HS04": "전적지·호국원",
    "NA01": "산·계곡·폭포", "NA02": "섬·해변·항구", "NA03": "노거수·지질 등 자연유산",
    "NA04": "휴양림·수목원·국립공원", "NA05": "산책로·드라이브길",
    "VE01": "전망대·등대·출렁다리", "VE02": "테마파크", "VE03": "공원",
    "VE04": "마을·테마거리", "VE05": "관광지구·리조트단지", "VE06": "공연장·아트홀",
    "VE07": "박물관·미술관", "VE09": "문화원·도서관", "VE10": "수련원·스포츠파크",
    "VE11": "기타", "VE12": "작은 전시·책방·안내소",
    "AC01": "호텔", "AC02": "콘도·리조트", "AC03": "펜션·한옥", "AC04": "모텔 등 기타 숙박",
    "AC05": "캠핑·야영장", "AC06": "유스호스텔·게스트하우스",
    "EX01": "전통·음식 체험", "EX02": "공예 체험", "EX03": "농산어촌 체험마을",
    "EX05": "온천·스파", "EX06": "산업·학습 체험관", "EX07": "기타 체험·놀거리",
    "LS01": "육상 레포츠", "LS02": "수상 레포츠", "LS03": "항공 레포츠", "LS04": "복합 레저시설",
    "SH02": "아울렛", "SH04": "대형·브랜드 상점", "SH05": "특산물·공예품점",
    "SH06": "전통시장·5일장", "SH07": "상점가",
    "EV01": "축제", "EV02": "공연", "EV03": "행사",
    "C0112": "추천 코스", "C0113": "추천 코스", "C0114": "추천 코스",
}
# ★ 말길 관점 재편 — 공사 분류가 아니라 「그곳에서 한국어를 쓰게 되는가」로 다시 묶은 것
말길구분 = {
    # VE09는 문화원 61 · 전수관/국악원/서당 26 · 도서관 27로 섞여 있다. 76%가 사람이
    # 설명해 주는 곳이라 「이야기」에 넣되, 도서관이 섞인 점을 산출물 주의에 적는다.
    "이야기": ["HS01", "HS02", "HS03", "HS04", "VE04", "VE07", "VE09", "VE12",
               "EX01", "EX03", "EX06", "SH06", "NA03"],
    "주문·흥정": ["FD01", "FD02", "FD03", "FD04", "FD05", "SH04", "SH05", "SH02", "SH07"],
    "말 없이도 되는 곳": ["NA01", "NA02", "NA04", "NA05", "VE01", "VE02", "VE03", "VE05",
                          "VE06", "VE10", "VE11", "EX02", "EX05", "EX07",
                          "LS01", "LS02", "LS03", "LS04",
                          "AC01", "AC02", "AC03", "AC04", "AC05", "AC06",
                          "EV01", "EV02", "EV03", "C0112", "C0113", "C0114"],
}
구분역인덱스 = {v: k for k, vs in 말길구분.items() for v in vs}
KOR유형 = {"12", "14", "15", "39"}      # kor 산식에 들어가는 contenttypeid


# 대전 원도심 철도 코스 — 기획서 §2-4 Lv3 예시. dump.json 국문 등재분에서 title로 찾는다
코스 = [
    ("대전역 동광장", "도착 · 1905년 경부선 대전역이 대전이라는 도시를 만들었다"),
    ("철도관사촌(솔랑시울길)", "★ 말벗 산책 구간 — 철도 노동자들이 살던 관사촌"),
    ("소제동", "관사촌이 있는 동네 이름 그 자체"),
    ("대전전통나래관", "소제동 · 앉아서 설명을 들어야 하는 유형"),
    ("소제동 카페 거리", "관사 건물을 그대로 쓴 카페 골목"),
    ("대동벽화마을", "언덕 위 동네 · 도보 15분"),
    ("대동하늘공원", "언덕 꼭대기 · 원도심이 한눈에 보인다"),
    ("대전 중앙시장", "전통시장 · 직접 주문하고 직접 계산한다"),
    ("신도칼국수 본점", "대전 칼국수"),
    ("오씨칼국수", "대전 칼국수"),
    ("으능정이문화의거리", "중구 은행동 · 지하철 2정거장"),
    ("성심당", "중구 은행동"),
]


# ── 읽기 ────────────────────────────────────────────────────
def ldong읽기():
    """공사 ldongCode2 목록 → parent 맵(일반구 → 시) · 기초지자체 집합 · 메타"""
    d = json.load(io.open(os.path.join(RAW, "ldong_269.json"), encoding="utf-8"))
    parent = {x["code5"]: x["parent"] for x in d["시군구"]}
    nm = {x["code5"]: x["nm"] for x in d["시군구"]}
    sido = {x["code5"]: x["sido"] for x in d["시군구"]}
    return parent, set(parent.values()), nm, sido, d


def r89읽기():
    """행안부 고시 인구감소지역 89곳 — 지정과제 ② 대응 대상 (기획서 §7-4)"""
    out = {}
    with io.open(os.path.join(RAW, "malgil_89_join.csv"), encoding="utf-8-sig") as f:
        for r in csv.DictReader(l for l in f if not l.startswith("#")):
            out[r["행정표준코드5"]] = r["시도"] + " " + r["시군구"]
    return out


def 인구읽기(parent):
    """주민등록 연령별 인구 → 시군구 5자리 코드별 {p5074, pop, e65}

    일반구 행(수원시 장안구 41111 …)은 건너뛴다 — 시 행(41110)이 따로 있어 더하면 이중 계상.
    인천 출장소 행(28114·28118·28265, 인구 0)은 기초지자체가 아니라 자연히 빠진다.
    """
    b5074 = ["50~54", "55~59", "60~64", "65~69", "70~74"]
    b65 = ["65~69", "70~74", "75~79", "80~84", "85~89", "90~94", "95~99", "100세 이상"]
    out = {}
    with io.open(os.path.join(RAW, "age_sgg_utf8.csv"), encoding="utf-8-sig") as f:
        for r in csv.DictReader(l for l in f if not l.startswith("#")):
            a = r["행정구역"]
            if "(" not in a:
                continue
            code10 = a.rsplit("(", 1)[1].rstrip(")").strip()
            if len(code10) != 10 or code10.endswith("00000000"):
                continue          # 시도 합계 행 제외 (P-DL02)
            code5 = code10[:5]
            if parent.get(code5, code5) != code5:
                continue          # 일반구 — 시 행이 따로 있다
            try:
                v = lambda k: int(r["2026년08월_계_%s" % k].replace(",", ""))
                pop = v("총인구수")
                p5074 = sum(v(b + "세") for b in b5074)
                o65 = sum(v(b if b.endswith("이상") else b + "세") for b in b65)
            except (KeyError, ValueError):
                continue
            t = out.setdefault(code5, {"p5074": 0, "pop": 0, "_o65": 0})
            t["p5074"] += p5074; t["pop"] += pop; t["_o65"] += o65
    for t in out.values():
        t["e65"] = round(t["_o65"] / t["pop"] * 100, 1) if t["pop"] else 0.0
        del t["_o65"]
    return out


def 코드정리(code, parent):
    """관광정보 코드를 기초지자체 코드에 맞춘다 — 일반구(41111)면 시(41110). 그 외는 그대로"""
    return parent.get(code, code)


def 관광자원읽기(parent, base, r89=None):
    """dump.json 국문 카탈로그 → 기초지자체별 유형 집계. 쇼핑(38)은 제외(P-M01)

    r89를 주면 인구감소지역 89곳의 lclsSystm 분류별 집계도 함께 만든다.
    반환: agg · 국문 행 · lDong 결측 수 · 89곳 분류 · 기초지자체 집합과 안 맞는 코드 Counter · dumped_at
    """
    d = json.load(io.open(os.path.join(RAW, "dump.json"), encoding="utf-8"))
    agg = collections.defaultdict(collections.Counter)
    분류 = collections.Counter()
    미매칭 = collections.Counter()
    rows = d["KorService2"]["items"]
    버림 = 0
    for r in rows:
        rg, sg = str(r.get("lDongRegnCd") or ""), str(r.get("lDongSignguCd") or "")
        if len(rg) == 5 and rg == sg:          # 세종특별자치시 — lDong이 5자리로 들어온다
            code = rg
        elif len(rg) == 2 and len(sg) == 3:
            code = rg + sg
        else:
            버림 += 1                          # lDong 결측 (areacode로도 복구 불가)
            continue
        code = 코드정리(code, parent)
        if code not in base:
            미매칭[code] += 1
        agg[code][str(r.get("contenttypeid"))] += 1
        if r89 is not None and code in r89:
            분류[(str(r.get("lclsSystm1") or "?"), str(r.get("lclsSystm2") or "?"),
                  str(r.get("contenttypeid")))] += 1
    return agg, rows, 버림, 분류, 미매칭, d.get("dumped_at", "2026-09-03")


def 방문자읽기():
    """analyze_visitor_gap.json — 기초지자체 230행. 병합·개편 보정은 그쪽에서 끝났다"""
    _raw = json.load(io.open(os.path.join(OUT, "analyze_visitor_gap.json"), encoding="utf-8"))
    rows = _raw["데이터"] if isinstance(_raw, dict) else _raw
    meta = _raw.get("_설명", {}) if isinstance(_raw, dict) else {}
    return {str(r["code"]): r for r in rows}, meta


# ── 급수 규칙 v2 ────────────────────────────────────────────
def 구분판정(nm):
    """이름 접미사로만. 일반구는 이미 시로 접혀 있으므로 남은 「구」는 자치구"""
    if nm.endswith("군"):
        return "군"
    if nm.endswith("구"):
        return "자치구"
    return "시"


def 천명중(share):
    n = round(share * 10)
    return "1명 미만" if n < 1 else "%d명" % n


def 천명중_en(share):
    n = round(share * 10)
    return "fewer than 1" if n < 1 else str(n)


def 급수배정(months, kor, share, 구분, pb, e65, rank_b, 그룹참고share,
             kor_t=KOR_T, share_t=SHARE_T, old65_t=OLD65_T, pb_t=PB_T):
    """급수 규칙 v2. 반환 (lv, 근거_ko, 근거_en) — 근거는 절대값 문장만 (백분율·백분위 서술 금지)"""
    구분_en = {"군": "county", "자치구": "urban district", "시": "city"}[구분]
    m10 = round((e65 or 0) / 10)
    if months < 12:
        ref = "" if 그룹참고share is None else " (묶음 참고: 방문자 1,000명 중 외국인 %s)" % 천명중(그룹참고share)
        ref_en = "" if 그룹참고share is None else " (group reference: %s foreign visitors per 1,000)" % 천명중_en(그룹참고share)
        return ("보류",
                "2026-07 신설 구 — 방문자 자료가 개편 후 %d개월뿐이라 판정 보류%s" % (months, ref),
                "District created Jul 2026 — only %d month of visitor data, on hold%s" % (months, ref_en))
    if kor < kor_t:
        return ("제외",
                "국문 관광자원 %d건 — %d건 미만이라 맵을 그릴 재료가 없다" % (kor, kor_t),
                "%d Korean-language tourism listings — fewer than %d, not enough to draw a map" % (kor, kor_t))
    if share >= share_t:
        return ("Lv1~2",
                "방문자 1,000명 중 외국인 %s — 50명 중 1명 이상이 외국인 · 국문 관광자원 %d건" % (천명중(share), kor),
                "%s foreign visitors per 1,000 — at least 1 in 50 · %d Korean-language listings" % (천명중_en(share), kor))
    if 구분 == "자치구":
        return ("Lv3",
                "방문자 1,000명 중 외국인 %s · 자치구 · 국문 관광자원 %d건" % (천명중(share), kor),
                "%s foreign visitors per 1,000 · urban district · %d Korean-language listings" % (천명중_en(share), kor))
    if pb is not None and pb >= pb_t:
        return ("Lv3",
                "방문자 1,000명 중 외국인 %s · %s · 내국인 방문 규모 전국 %d위 · 국문 관광자원 %d건" % (천명중(share), 구분, rank_b, kor),
                "%s foreign visitors per 1,000 · %s · #%d nationwide in domestic visitors · %d Korean-language listings" % (천명중_en(share), 구분_en, rank_b, kor))
    if 구분 == "군" and (e65 or 0) >= old65_t:
        return ("Lv5",
                "방문자 1,000명 중 외국인 %s · 군 · 주민 10명 중 %d명이 65세 이상 · 국문 관광자원 %d건" % (천명중(share), m10, kor),
                "%s foreign visitors per 1,000 · county · %d in 10 residents aged 65+ · %d Korean-language listings" % (천명중_en(share), m10, kor))
    return ("Lv4",
            "방문자 1,000명 중 외국인 %s · %s · 주민 10명 중 %d명이 65세 이상 · 국문 관광자원 %d건" % (천명중(share), 구분, m10, kor),
            "%s foreign visitors per 1,000 · %s · %d in 10 residents aged 65+ · %d Korean-language listings" % (천명중_en(share), 구분_en, m10, kor))


def 급수만(x, **kw):
    return 급수배정(x["months"], x["kor"], x["share"], x["구분"], x["pb"], x["e65"], x["rank_b"], x["그룹참고share"], **kw)[0]


def 셈(rows, lv, **kw):
    """상수를 바꿔 다시 매겼을 때 lv 인 곳 수 — (전체, 89곳)"""
    a = [급수만(x, **kw) == lv for x in rows]
    return sum(a), sum(1 for x, ok in zip(rows, a) if ok and x["is89"])


def main():
    parent, base, ldnm, ldsido, ld = ldong읽기()
    인구 = 인구읽기(parent)
    r89 = r89읽기()
    vis, vmeta = 방문자읽기()
    agg, korrows, 버림, 분류, 미매칭, 실측일 = 관광자원읽기(parent, base, r89)

    r89미매칭 = sorted(c for c in r89 if c not in base)
    vis미매칭 = sorted(c for c in vis if c not in base)
    base미수록 = sorted(c for c in base if c not in vis)

    후보 = []
    for code in sorted(base):
        v = vis.get(code)
        if v is None:
            continue
        c = agg.get(code, collections.Counter())
        kor = c["12"] + c["14"] + c["15"] + c["39"]
        nm = ldnm.get(code, v["nm"])
        p = 인구.get(code, {"p5074": 0, "pop": 0, "e65": 0.0})
        x = {
            "code": code,
            "sido": ldsido.get(code, v.get("sido", "?")),
            "nm": nm,
            "구분": 구분판정(nm),
            "kor": kor,
            "t12": c["12"], "t14": c["14"], "t15": c["15"], "t39": c["39"],
            "share": v["share"],
            "pb": v.get("pb"), "ps": v.get("ps"), "gap": v.get("gap"), "rank_b": v.get("rank_b"),
            "months": v["months"],
            "그룹참고share": v.get("그룹참고share"),
            "pop": p["pop"], "p5074": p["p5074"], "e65": p["e65"],
            "is89": code in r89,
        }
        x["lv"], x["근거_ko"], x["근거_en"] = 급수배정(
            x["months"], x["kor"], x["share"], x["구분"], x["pb"], x["e65"], x["rank_b"], x["그룹참고share"])
        후보.append(x)
    후보.sort(key=lambda x: (x["months"] < 12, x["share"], -x["kor"]))

    # ── 요약 · 감도표 ─────────────────────────────────────────
    cnt전체 = collections.Counter(x["lv"] for x in 후보)
    cnt89 = collections.Counter(x["lv"] for x in 후보 if x["is89"])
    급수별곳수 = {lv: {"전체": cnt전체.get(lv, 0), "89곳": cnt89.get(lv, 0)} for lv in LV_ORDER}
    누적 = []
    acc_all = acc_89 = 0
    for u in 사용자급수:
        acc_all += cnt전체.get(u, 0); acc_89 += cnt89.get(u, 0)
        누적.append({"사용자급수": u, "열린lv": " + ".join(사용자급수[:사용자급수.index(u) + 1]),
                   "전체": acc_all, "89곳": acc_89})
    감도_e65 = []
    for t in (35.0, 38.0, 40.0, 42.0, 45.0):
        a, b = 셈(후보, "Lv5", old65_t=t)
        감도_e65.append({"OLD65_T": t, "Lv5_전체": a, "Lv5_89곳": b, "채택": t == OLD65_T})
    감도_share = []
    for t in (1.5, 2.0, 2.5, 3.0):
        a, b = 셈(후보, "Lv1~2", share_t=t)
        감도_share.append({"SHARE_T": t, "Lv1~2_전체": a, "Lv1~2_89곳": b, "채택": t == SHARE_T})
    급수규칙 = {
        "상수": {"KOR_T": KOR_T, "SHARE_T": SHARE_T, "OLD65_T": OLD65_T, "PB_T": PB_T},
        "순서": ["months < 12 → 보류", "kor < KOR_T → 제외", "share ≥ SHARE_T → Lv1~2",
                 "구분 = 자치구 or pb ≥ PB_T → Lv3", "구분 = 군 and e65 ≥ OLD65_T → Lv5", "나머지 → Lv4"],
        "감도_e65": 감도_e65,
        "감도_share": 감도_share,
    }
    요약 = {"기초지자체": len(후보), "인구감소지역": sum(1 for x in 후보 if x["is89"]),
          "급수별곳수": 급수별곳수, "사용자급수별누적열린곳": 누적}

    # ── 대전 원도심 코스 — 국문 카탈로그에 실제로 등재된 행만 남긴다 ──
    idx = {}
    for r in korrows:
        if str(r.get("lDongRegnCd") or "") == "30":
            idx.setdefault(r["title"].strip(), r)
    정류장 = []
    for title, note in 코스:
        r = idx.get(title)
        정류장.append({
            "정류장": title,
            "등재": bool(r),
            "contentid": (r or {}).get("contentid", ""),
            "유형": 유형.get(str((r or {}).get("contenttypeid")), str((r or {}).get("contenttypeid", ""))),
            "주소": (r or {}).get("addr1", ""),
            "메모": note,
        })

    # ── 89곳 자원 분류 ────────────────────────────────────────
    자원 = []
    총 = sum(분류.values())
    묶음 = collections.Counter()
    for (a, b, t), n in 분류.items():
        묶음[(a, b)] += n
    for (a, b), n in sorted(묶음.items(), key=lambda x: -x[1]):
        유형코드 = sorted({t for (aa, bb, t) in 분류 if aa == a and bb == b})
        자원.append({
            "대분류": a, "대분류명": 대분류.get(a, "?"),
            "중분류": b, "중분류명": 중분류.get(b, "?"),
            "건수": n,
            "비중%": round(n / 총 * 100, 2),
            "contenttypeid": "·".join(유형코드),
            "kor포함": bool(set(유형코드) & KOR유형),
            "말길구분": 구분역인덱스.get(b, "미분류"),
        })

    # ── 예시용 실제 행 (자기설명 규칙: 가상값 금지) ─────────────
    by = {x["code"]: x for x in 후보}
    def pick(code, cond=None):
        if code in by:
            return by[code]
        return next(x for x in 후보 if cond(x))
    ex대전 = pick("30140")                                   # 대전 중구
    ex구례 = pick("12730")                                   # 구례군
    ex군위 = pick("27720")                                   # 대구 군위군 — 광역시 소속 군
    ex인천 = pick("28125", lambda x: x["months"] < 12)       # 인천 제물포구 — 보류
    ex5 = next((x for x in 후보 if x["lv"] == "Lv5" and x["is89"]), ex구례)
    ex4 = next((x for x in 후보 if x["lv"] == "Lv4" and x["is89"]), ex구례)
    ex12 = next((x for x in 후보 if x["lv"] == "Lv1~2" and x["is89"]), 후보[-1])
    ex3시 = next((x for x in 후보 if x["lv"] == "Lv3" and x["구분"] != "자치구"), ex대전)
    ex제외 = next((x for x in 후보 if x["lv"] == "제외"), None)
    def S(x):
        return "%s %s" % (x["sido"][:2], x["nm"])

    설명 = {
        "파일": "analyze_topik_local.json",
        "무엇": "TOPIK 급수별로 갈 수 있는 로컬 지역 판별 (급수 규칙 v2) — 급수후보 · 급수규칙 · 요약 · 대전원도심코스 · 89곳자원분류",
        "생성일": 생성일,
        "생성": "python data/AI/analyze_topik_local.py",
        "입력": "AI/_raw/dump.json (TourAPI 국문 전량 실측 %s · 국문 %s건) · AI/_raw/ldong_269.json (ldongCode2 %s 실측 · 시군구 %d → 기초 %d) · AI/_raw/age_sgg_utf8.csv (주민등록 2026년 8월) · AI/_raw/malgil_89_join.csv · 인간/analyze_visitor_gap.json (%s 산출 · 기초지자체 %d행 · 방문자 2025-08~2026-07)" % (
            실측일, format(len(korrows), ","), ld.get("pulled_at", "?"), ld["n_sgg"], len(base), vmeta.get("생성일", "?"), len(vis)),
        "왜 영문 카탈로그를 쓰지 않는가": "영문 등재 여부로 장소의 열림/닫힘을 판정하면 중국어·일본어·베트남어권 방문자를 전부 영어권으로 치환하게 된다. 그 지표가 재는 값은 「영어 번역 진척도」이지 「한국어가 필요한 정도」가 아니다. 그래서 카탈로그의 언어가 아니라 누가 실제로 오는가(외국인 방문 비중)로 잰다 — 기획서 P-M04. dump.json 의 EngService2 는 이 스크립트가 읽지 않는다",
        "주의": [
            "P-DL01 총량 사용 금지 — 방문자는 구성비(share)와 백분위(pb)·순위(rank_b)로만 해석한다. 근거 문장도 절대값 표현(1,000명 중 N명)만 쓴다",
            "P-DL02 기초 ↔ 광역 합산 금지 — 기초지자체끼리만 비교",
            "P-DL03 「방문자」는 「관광객」이 아니다",
            "P-M01 관광자원 두께에서 쇼핑(국문 38)을 제외했다 — 사후면세점 아티팩트",
            "기초지자체 집합은 공사 ldongCode2 시군구 %d에서 일반구 %d곳을 시로 접은 %d곳이다 (analyze_visitor_gap.json 과 동일). 관광정보의 일반구 코드(수원시 장안구 41111 등)도 같은 규칙으로 시에 합쳤다" % (ld["n_sgg"], ld.get("n_gu", 0), len(base)),
            "인천 2026-07 신설 4구(제물포·영종·서해·검단)는 방문자 자료가 개편 후 1개월뿐이라 「보류」. 구코드(28110·28140·28260)는 산출물에 없다",
            "구분(군·자치구·시)은 이름 접미사로만 정한다. 이전 판(2026-09-10)은 광역시 코드면 전부 자치구로 잡아 대구 군위군·달성군, 인천 강화군·옹진군, 부산 기장군, 울산 울주군이 자치구로 오분류됐다 — 이번 판에서 바로잡았다",
            "급수 규칙 v2는 백분위(ps)를 쓰지 않는다. ps·gap 열은 참고로만 남겼다",
            "급수 배정은 지역 단위 후보 추림이다. 장소 단위 PLL 판정(기획서 §4-3)은 이 산출물의 범위가 아니다",
            "기초지자체 집합 대조 — 89곳 중 미매칭 %s · 방문자 행 중 미매칭 %s · 방문자 자료 없는 기초 %s · 관광정보 중 기초 집합 밖 코드 %s" % (
                r89미매칭 or "0건", vis미매칭 or "0건", base미수록 or "0건",
                ", ".join("%s(%d건)" % kv for kv in sorted(미매칭.items())) or "0건"),
            "lDong 결측으로 버린 관광정보 %d건" % 버림,
        ],
        "섹션": {
            "급수후보": {
                "무엇": "기초지자체 %d곳을 급수 규칙 v2로 배정한 결과" % len(후보),
                "정렬": "완전월 행을 share 오름차순 (외국인 비중이 낮은 곳부터 = 한국어가 기본값인 곳부터) → 보류 행은 맨 뒤",
                "행수": len(후보),
                "항목": {
                    "code": {"뜻": "행정표준코드 5자리 (공사 ldongCode2 기준 신코드)", "산식": "원자료", "범위": "5자리 숫자 문자열", "단위": "코드",
                             "예시": "%s = %s %s" % (ex대전["code"], ex대전["sido"], ex대전["nm"])},
                    "sido": {"뜻": "시도명 (ldongCode2 기준 16개)", "산식": "원자료", "범위": "-", "단위": "문자열",
                             "예시": "%s · 구례군은 「%s」" % (ex대전["sido"], ex구례["sido"])},
                    "nm": {"뜻": "시군구명", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": ex대전["nm"]},
                    "구분": {"뜻": "군 · 자치구 · 시", "산식": "이름 접미사 — 「군」이면 군, 「구」면 자치구(일반구는 이미 시로 접혔다), 나머지 시. 광역 코드 집합은 쓰지 않는다",
                             "범위": "군/자치구/시", "단위": "문자열",
                             "예시": "%s = %s (광역시 소속이지만 군) · %s = %s" % (S(ex군위), ex군위["구분"], S(ex대전), ex대전["구분"])},
                    "kor": {"뜻": "국문 관광자원 두께 — 실제로 갈 곳이 있는가", "산식": "t12 + t14 + t15 + t39 (쇼핑 제외 · P-M01)",
                            "범위": "0 이상", "단위": "건",
                            "예시": "%s %d건 = 관광지 %d + 문화시설 %d + 축제 %d + 음식점 %d" % (S(ex대전), ex대전["kor"], ex대전["t12"], ex대전["t14"], ex대전["t15"], ex대전["t39"])},
                    "t12": {"뜻": "관광지 등재 건수", "산식": "contenttypeid=12 집계", "범위": "0 이상", "단위": "건", "예시": "%s %d건" % (S(ex구례), ex구례["t12"])},
                    "t14": {"뜻": "문화시설 등재 건수", "산식": "contenttypeid=14 집계", "범위": "0 이상", "단위": "건", "예시": "%s %d건" % (S(ex구례), ex구례["t14"])},
                    "t15": {"뜻": "축제공연행사 등재 건수", "산식": "contenttypeid=15 집계", "범위": "0 이상", "단위": "건", "예시": "%s %d건" % (S(ex구례), ex구례["t15"])},
                    "t39": {"뜻": "음식점 등재 건수", "산식": "contenttypeid=39 집계", "범위": "0 이상", "단위": "건", "예시": "%s %d건" % (S(ex구례), ex구례["t39"])},
                    "share": {"뜻": "★ 외국인 방문 비중 — 낮을수록 그 동네의 기본 언어가 한국어. 급수 규칙의 Lv1~2 기준축",
                              "산식": "외국인 / (외지인 + 외국인) × 100 · 집계 개월 누계 (analyze_visitor_gap.json)",
                              "범위": "0~100", "단위": "%",
                              "예시": "%s %.3f%% — 방문자 1,000명 중 외국인 %s" % (S(ex구례), ex구례["share"], 천명중(ex구례["share"]))},
                    "pb": {"뜻": "내국인 방문 규모의 백분위 — 시·군의 Lv3 판정축(PB_T=%d)" % PB_T,
                           "산식": "완전월 기초지자체 중 외지인 방문지표의 백분위", "범위": "0~100 또는 null(보류 행)", "단위": "백분위",
                           "예시": "%s %s — 시·군인데 내국인 왕래가 많아 Lv3" % (S(ex3시), ex3시["pb"])},
                    "ps": {"뜻": "외국인 비중의 백분위 (참고 — v2 규칙에서는 쓰지 않는다)", "산식": "완전월 기초지자체 중 share의 백분위",
                           "범위": "0~100 또는 null", "단위": "백분위", "예시": "%s %s" % (S(ex구례), ex구례["ps"])},
                    "gap": {"뜻": "격차 — 클수록 「내국인은 오는데 외국인은 안 오는 곳」 (참고)", "산식": "pb − ps",
                            "범위": "-100~100 또는 null", "단위": "백분위 차", "예시": "%s %s" % (S(ex대전), ex대전["gap"])},
                    "rank_b": {"뜻": "내국인 방문 규모 순위 — 근거 문장에서 백분위 대신 쓰는 절대값", "산식": "완전월 기초지자체 중 외지인 방문지표 내림차순 순위",
                               "범위": "1 이상 또는 null", "단위": "위", "예시": "%s %s위" % (S(ex3시), ex3시["rank_b"])},
                    "months": {"뜻": "방문자 집계에 잡힌 개월 수. 12 미만이면 보류", "산식": "원자료 집계", "범위": "1~12", "단위": "개월",
                               "예시": "%s %d개월 · %s %d개월" % (S(ex구례), ex구례["months"], S(ex인천), ex인천["months"])},
                    "그룹참고share": {"뜻": "인천 신설 4구에만 있는 참고값 — 개편 전 구코드+신코드 묶음 합산 외국인 비중. 판정에는 쓰지 않는다",
                                  "산식": "analyze_visitor_gap.json 그대로", "범위": "0~100 또는 null", "단위": "%",
                                  "예시": "%s %s%%" % (S(ex인천), ex인천["그룹참고share"])},
                    "pop": {"뜻": "주민등록 총인구", "산식": "주민등록 2026년 8월 총인구수", "범위": "0 이상", "단위": "명",
                            "예시": "%s %s명" % (S(ex구례), format(ex구례["pop"], ","))},
                    "p5074": {"뜻": "50~74세 인구 — 말벗 공급 모수", "산식": "주민등록 연령별 인구 5개 구간 합 (2026년 8월)",
                              "범위": "0 이상", "단위": "명", "예시": "%s %s명" % (S(ex구례), format(ex구례["p5074"], ","))},
                    "e65": {"뜻": "65세 이상 인구 비율 — 군의 Lv5 판정축(OLD65_T=%.0f)" % OLD65_T,
                            "산식": "65세 이상 8개 구간 합 / 총인구 × 100 (소수 1자리)", "범위": "0~100", "단위": "%",
                            "예시": "%s %.1f%% — 주민 10명 중 %d명이 65세 이상" % (S(ex5), ex5["e65"], round(ex5["e65"] / 10))},
                    "is89": {"뜻": "행안부 고시 인구감소지역 89곳인가 — 지정과제 ② 대응 대상",
                             "산식": "malgil_89_join.csv 행정표준코드 대조", "범위": "true / false", "단위": "불리언",
                             "예시": "%s true · %s false" % (S(ex구례), S(ex대전))},
                    "lv": {"뜻": "배정된 급수 맵 칸 (급수 규칙 v2)", "산식": "급수규칙 섹션의 순서대로 첫 조건에 걸리는 칸",
                           "범위": "Lv1~2 · Lv3 · Lv4 · Lv5 · 제외 · 보류", "단위": "구분",
                           "예시": "%s %s · %s %s · %s %s · %s %s" % (S(ex12), ex12["lv"], S(ex대전), ex대전["lv"], S(ex4), ex4["lv"], S(ex5), ex5["lv"])},
                    "근거_ko": {"뜻": "그 급수로 배정된 이유 — 절대값 문장만 (백분율·백분위 서술 없음)", "산식": "lv 분기 서술", "범위": "-", "단위": "문자열",
                                "예시": "%s — 「%s」" % (S(ex5), ex5["근거_ko"])},
                    "근거_en": {"뜻": "근거_ko의 영문 (앱 표시용)", "산식": "lv 분기 서술", "범위": "-", "단위": "문자열",
                                "예시": "%s — \"%s\"" % (S(ex5), ex5["근거_en"])},
                },
            },
            "급수규칙": {
                "무엇": "급수 규칙 v2의 상수 4개 · 적용 순서 · 상수를 바꿨을 때 곳수가 얼마나 흔들리는지(감도표)",
                "정렬": "감도표는 상수 오름차순",
                "행수": "감도_e65 %d행 · 감도_share %d행" % (len(감도_e65), len(감도_share)),
                "항목": {
                    "상수": {"뜻": "KOR_T 국문 자원 최소 건수 · SHARE_T 외국인 비중 문턱(%) · OLD65_T 65세 이상 비율 문턱(%) · PB_T 내국인 방문 백분위 문턱",
                             "산식": "고정값", "범위": "-", "단위": "건 · % · % · 백분위",
                             "예시": "SHARE_T %.1f = 방문자 50명 중 1명 · OLD65_T %.0f = 주민 10명 중 4명" % (SHARE_T, OLD65_T)},
                    "감도_e65.OLD65_T": {"뜻": "Lv5 문턱을 이 값으로 바꾸면", "산식": "다른 상수 고정 · 전 행 재배정", "범위": "35~45", "단위": "%",
                                       "예시": "OLD65_T %.0f → Lv5 전체 %d곳 · 89곳 %d곳 (채택값)" % (OLD65_T, 급수별곳수["Lv5"]["전체"], 급수별곳수["Lv5"]["89곳"])},
                    "감도_e65.Lv5_전체 · Lv5_89곳": {"뜻": "그때 Lv5 가 되는 곳 수", "산식": "count(lv = Lv5)", "범위": "0~%d" % len(후보), "단위": "곳",
                                                  "예시": "OLD65_T 35 → 전체 %d · 89곳 %d" % (감도_e65[0]["Lv5_전체"], 감도_e65[0]["Lv5_89곳"])},
                    "감도_share.SHARE_T": {"뜻": "Lv1~2 문턱을 이 값으로 바꾸면", "산식": "다른 상수 고정 · 전 행 재배정", "범위": "1.5~3.0", "단위": "%",
                                         "예시": "SHARE_T %.1f → Lv1~2 전체 %d곳 · 89곳 %d곳 (채택값)" % (SHARE_T, 급수별곳수["Lv1~2"]["전체"], 급수별곳수["Lv1~2"]["89곳"])},
                    "감도_share.Lv1~2_전체 · Lv1~2_89곳": {"뜻": "그때 Lv1~2 가 되는 곳 수", "산식": "count(lv = Lv1~2)", "범위": "0~%d" % len(후보), "단위": "곳",
                                                       "예시": "SHARE_T 3.0 → 전체 %d · 89곳 %d" % (감도_share[-1]["Lv1~2_전체"], 감도_share[-1]["Lv1~2_89곳"])},
                    "채택": {"뜻": "현재 상수와 같은 행인가", "산식": "값 == 상수", "범위": "true / false", "단위": "불리언", "예시": "OLD65_T 40.0 true"},
                },
            },
            "요약": {
                "무엇": "급수별 곳수(전체·89곳)와 사용자 급수별 누적 열린 곳수 — 문서에 인용할 대표 수치",
                "정렬": "LV_ORDER (Lv1~2 → Lv3 → Lv4 → Lv5 → 제외 → 보류)",
                "행수": "급수별곳수 %d칸 · 사용자급수별누적열린곳 %d행" % (len(LV_ORDER), len(누적)),
                "항목": {
                    "기초지자체 · 인구감소지역": {"뜻": "판정 대상 곳수", "산식": "count", "범위": "-", "단위": "곳",
                                          "예시": "기초지자체 %d · 인구감소지역 %d" % (요약["기초지자체"], 요약["인구감소지역"])},
                    "급수별곳수": {"뜻": "각 급수 칸에 떨어진 곳 수", "산식": "count(lv) · 전체와 89곳 따로", "범위": "0~%d" % len(후보), "단위": "곳",
                                "예시": "Lv5 전체 %d곳 · 89곳 %d곳" % (급수별곳수["Lv5"]["전체"], 급수별곳수["Lv5"]["89곳"])},
                    "사용자급수별누적열린곳": {"뜻": "TOPIK 급수가 그 칸인 사용자에게 열린 지역 수 — 자기 급수 이하 칸의 합. Lv5 사용자는 전부(제외·보류 제외)",
                                         "산식": "누적 count(lv ≤ 사용자급수)", "범위": "0~%d" % len(후보), "단위": "곳",
                                         "예시": "Lv3 사용자 → 전체 %d곳 · 89곳 %d곳 (Lv1~2 + Lv3)" % (누적[1]["전체"], 누적[1]["89곳"])},
                },
            },
            "89곳자원분류": {
                "무엇": "인구감소지역 89곳에 국문 카탈로그로 등재된 콘텐츠를 공사 분류체계(lclsSystm) 중분류로 쪼갠 결과",
                "정렬": "건수 내림차순",
                "행수": len(자원),
                "주의": [
                    "★ 이 표는 「그 지역에 관광 자원이 실재한다」가 아니라 「카탈로그에 등재된 건수」를 센다. 등재는 지자체·사업자의 등록 성실도에 좌우된다",
                    "★ 중분류명·대분류명은 공사가 코드만 내려주어 89곳 title 표본을 직접 읽고 붙인 이름이다. 공사 공식 명칭이 아니다",
                    "kor(급수 배정에 쓰는 국문 관광자원 두께)은 contenttypeid 12·14·15·39만 더한 값이라 숙박(32)·레포츠(28)·쇼핑(38)·코스(25)는 빠진다 — kor포함 열로 구분",
                    "말길구분은 공사 분류가 아니라 우리가 붙인 것이다. VE09는 문화원·전수관·도서관이 섞여 있어 다수를 따라 「이야기」에 넣었다",
                ],
                "항목": {
                    "대분류": {"뜻": "lclsSystm1 코드", "산식": "원자료", "범위": "FD·HS·NA·VE·AC·EX·LS·SH·EV·C01",
                               "단위": "코드", "예시": "%s = %s" % (자원[0]["대분류"], 자원[0]["대분류명"])},
                    "대분류명": {"뜻": "대분류의 한국어 이름 (표본으로 붙인 이름)", "산식": "title 표본 판독",
                                 "범위": "-", "단위": "문자열", "예시": "HS → 역사"},
                    "중분류": {"뜻": "lclsSystm2 코드", "산식": "원자료", "범위": "-", "단위": "코드", "예시": 자원[0]["중분류"]},
                    "중분류명": {"뜻": "중분류의 한국어 이름 (표본으로 붙인 이름)", "산식": "title 표본 판독",
                                 "범위": "-", "단위": "문자열", "예시": "%s → %s" % (자원[0]["중분류"], 자원[0]["중분류명"])},
                    "건수": {"뜻": "89곳 합계 등재 건수", "산식": "원자료 집계", "범위": "1 이상", "단위": "건",
                             "예시": "%s %s %s건 — 89곳 전체에서 가장 많은 분류" % (자원[0]["중분류"], 자원[0]["중분류명"], format(자원[0]["건수"], ","))},
                    "비중%": {"뜻": "89곳 등재 전체에서 차지하는 몫", "산식": "건수 / %s × 100" % format(총, ","),
                              "범위": "0~100", "단위": "%", "예시": "%s %.2f%%" % (자원[0]["중분류"], 자원[0]["비중%"])},
                    "contenttypeid": {"뜻": "그 중분류에 실제로 붙은 콘텐츠 유형 코드", "산식": "원자료 집계",
                                      "범위": "12·14·15·25·28·32·38·39", "단위": "코드",
                                      "예시": "%s = %s" % (자원[0]["중분류"], 자원[0]["contenttypeid"])},
                    "kor포함": {"뜻": "급수 배정용 kor 산식(12·14·15·39)에 들어가는가",
                                "산식": "contenttypeid ∩ {12,14,15,39} ≠ ∅", "범위": "true / false", "단위": "불리언",
                                "예시": "SH06 전통시장 false — 쇼핑(38)이라 kor에서 빠진다"},
                    "말길구분": {"뜻": "★ 공사 분류가 아니라 「그곳에서 한국어를 쓰게 되는가」로 다시 묶은 것",
                                 "산식": "이야기(설명을 들어야 의미가 생김) · 주문·흥정(직접 말해야 함) · 말 없이도 되는 곳",
                                 "범위": "이야기 / 주문·흥정 / 말 없이도 되는 곳", "단위": "구분",
                                 "예시": "HS01 서원·고택 → 이야기 (말벗 세션 대상) · NA02 섬·해변 → 말 없이도 되는 곳"},
                },
            },
            "대전원도심코스": {
                "무엇": "기획서 §2-4 Lv3 예시로 쓰는 대전 원도심 철도 코스 12정류장이 국문 카탈로그에 실제로 등재돼 있는지 대조한 결과",
                "정렬": "코스 진행 순서",
                "행수": len(정류장),
                "항목": {
                    "정류장": {"뜻": "코스의 정류장 이름", "산식": "국문 카탈로그 title 원문", "범위": "-", "단위": "문자열",
                               "예시": 정류장[1]["정류장"]},
                    "등재": {"뜻": "국문 관광정보에 등재돼 있는가", "산식": "dump.json KorService2 title 완전일치",
                             "범위": "true / false", "단위": "불리언",
                             "예시": "%s %s — contentid %s" % (정류장[1]["정류장"], 정류장[1]["등재"], 정류장[1]["contentid"] or "-")},
                    "contentid": {"뜻": "공사 콘텐츠 ID", "산식": "원자료", "범위": "-", "단위": "ID",
                                  "예시": "%s = %s" % (정류장[7]["정류장"], 정류장[7]["contentid"] or "-")},
                    "유형": {"뜻": "콘텐츠 유형", "산식": "contenttypeid 대응(12 관광지 · 14 문화시설 · 15 축제 · 39 음식점)",
                             "범위": "-", "단위": "문자열", "예시": "%s = %s" % (정류장[1]["정류장"], 정류장[1]["유형"] or "-")},
                    "주소": {"뜻": "등재 주소", "산식": "원자료 addr1", "범위": "-", "단위": "문자열",
                             "예시": 정류장[1]["주소"] or "-"},
                    "메모": {"뜻": "그 정류장이 코스에서 하는 역할", "산식": "기획서 §2-4 서술", "범위": "-", "단위": "문자열",
                             "예시": "철도관사촌 — 「말벗 산책 구간」"},
                },
            },
        },
    }

    json.dump({"_설명": 설명, "데이터": {"급수후보": 후보, "급수규칙": 급수규칙, "요약": 요약,
                                        "대전원도심코스": 정류장, "89곳자원분류": 자원}},
              io.open(os.path.join(OUT, "analyze_topik_local.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    # ── 콘솔 요약 ─────────────────────────────────────────────
    print("기초지자체 %d곳 (ldongCode2 %d → 일반구 %d 접음 → %d · 방문자 행 %d) · 89곳 %d"
          % (len(후보), ld["n_sgg"], ld.get("n_gu", 0), len(base), len(vis), 요약["인구감소지역"]))
    print("대조: 89곳 미매칭 %s · 방문자 미매칭 %s · 방문자 없는 기초 %s · 관광정보 기초 밖 코드 %s"
          % (r89미매칭 or 0, vis미매칭 or 0, base미수록 or 0, dict(미매칭) or 0))
    print("lDong 결측으로 버린 관광정보 %d건 · 실측일 %s" % (버림, 실측일))
    print("급수 전체 %s" % {lv: cnt전체.get(lv, 0) for lv in LV_ORDER})
    print("급수 89곳 %s (합 %d)" % ({lv: cnt89.get(lv, 0) for lv in LV_ORDER}, sum(cnt89.values())))
    print("사용자 급수별 누적 열린 곳: " + " · ".join("%s → 전체 %d / 89곳 %d" % (u["사용자급수"], u["전체"], u["89곳"]) for u in 누적))
    print("감도 e65  : " + " · ".join("%.0f→%d/%d" % (s["OLD65_T"], s["Lv5_전체"], s["Lv5_89곳"]) for s in 감도_e65))
    print("감도 share: " + " · ".join("%.1f→%d/%d" % (s["SHARE_T"], s["Lv1~2_전체"], s["Lv1~2_89곳"]) for s in 감도_share))
    print("\n외국인 비중 최저 12곳 (한국어가 기본값인 곳)")
    for x in 후보[:12]:
        print("  %-6s %-4s %-8s share=%.3f%% pb=%5.1f kor=%3d e65=%4.1f %-4s %s"
              % (x["code"], x["sido"][:2], x["nm"], x["share"], x["pb"], x["kor"], x["e65"], x["구분"], x["lv"]))
    print("\n광역시 소속 군 · 인천 신설 4구")
    for x in 후보:
        if (x["nm"].endswith("군") and x["code"][:2] in {"26", "27", "28", "31"}) or x["months"] < 12:
            print("  %-6s %-4s %-6s %-4s months=%2d share=%7.3f%% 참고=%s kor=%3d e65=%4.1f %s"
                  % (x["code"], x["sido"][:2], x["nm"], x["구분"], x["months"], x["share"], x["그룹참고share"], x["kor"], x["e65"], x["lv"]))
    print("\n대전 5개 구")
    for x in sorted((x for x in 후보 if x["code"].startswith("30")), key=lambda x: x["code"]):
        print("  %-6s %-8s share=%.3f%% pb=%.1f kor=%3d p5074=%-8s %s" % (x["code"], x["nm"], x["share"], x["pb"], x["kor"], format(x["p5074"], ","), x["lv"]))
    미등재 = [s["정류장"] for s in 정류장 if not s["등재"]]
    print("\n대전 원도심 코스 %d정류장 · 국문 등재 %d / 미등재 %d %s"
          % (len(정류장), len(정류장) - len(미등재), len(미등재), 미등재 or ""))
    print("\nOK -> %s" % os.path.join(OUT, "analyze_topik_local.json"))


if __name__ == "__main__":
    main()
