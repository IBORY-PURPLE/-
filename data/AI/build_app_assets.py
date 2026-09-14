# -*- coding: utf-8 -*-
"""
말길 · 앱 자산 빌더 (P7~P8)

  무엇   급수 판정 결과(analyze_topik_local.json) + 공사 시군구 목록(ldong_269.json)
         + 시군구 경계(sgg_20260701_light.parquet) 를 하나의 JSON 으로 묶어 Flutter 앱 자산으로 낸다.
         경계는 WKB(WGS84) 를 직접 디코드해 viewBox 0 0 1000 1300 정수 좌표로 투영한다.

  입력   인간/analyze_topik_local.json   급수후보 230 · 급수규칙 · 요약     (analyze_topik_local.py)
         AI/_raw/ldong_269.json          공사 ldongCode2 시군구 269 (시 230 + 일반구 39)  (pull_ldong.py)
         AI/_raw/malgil_89_join.csv      행안부 인구감소지역 89곳
         AI/_raw/sgg_20260701_light.parquet  시군구 경계 256 (vuski/admdongkor · CC BY 4.0)

  출력   app/flutter/assets/data/build_app_assets.json   (앱이 rootBundle 로 읽음)
         --mockup  →  Docs/mockup/data.js  = 'window.MALGIL = <같은 JSON>;'  (file:// 로 여는 목업용)

  실행   python data/AI/build_app_assets.py            앱 자산만
         python data/AI/build_app_assets.py --mockup   앱 자산 + 목업 data.js
         python data/AI/build_app_assets.py --eps 1.5  단순화 허용오차(px) 바꿔 보기

  규칙   1 스크립트 = 1 파일 (data.js 는 같은 내용의 JS 래퍼) · _설명 첫 키 · 섹션 = 데이터 아래
         89곳 전부 경계가 있어야 한다 — 없으면 실패(exit 1)
         외부 라이브러리는 numpy · pyarrow 만 (shapely · pyproj 없이 WKB 를 struct 로 읽는다)
"""
import io, os, sys, csv, json, math, struct, argparse, datetime
import numpy as np
import pyarrow.parquet as pq

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
ROOT = os.path.dirname(os.path.dirname(HERE))             # 프로젝트 루트
APP_ASSET = os.path.join(ROOT, "app", "flutter", "assets", "data", "build_app_assets.json")
MOCKUP_JS = os.path.join(ROOT, "Docs", "mockup", "data.js")

TOPIK = os.path.join(OUT, "analyze_topik_local.json")
LDONG = os.path.join(RAW, "ldong_269.json")
JOIN89 = os.path.join(RAW, "malgil_89_join.csv")
PARQ = os.path.join(RAW, "sgg_20260701_light.parquet")

VIEW_W, VIEW_H = 1000, 1300
COS_LAT = math.cos(math.radians(36.0))          # 위도 36° 기준 경도 축소 (한반도 중앙)
EPS_PX = 0.5                                     # Douglas-Peucker 허용오차 (viewBox px) — 0.5px ≈ 0.33km · JSON ≤ 500KB 안
DOT_PX = 2                                       # 정수화 후 점으로 줄어든 섬을 그릴 삼각형 한 변
PAD_PX = 3                                       # viewBox 가장자리 여백 (점 링이 밖으로 나가지 않게)
LV_ORDER = ["Lv1~2", "Lv3", "Lv4", "Lv5", "제외", "보류"]
COPY_FIELDS = ["구분", "lv", "근거_ko", "근거_en", "share", "pb", "kor", "e65", "pop", "is89", "months"]


# ───────────────────────── WKB ─────────────────────────
def _ring(buf, off, bo):
    n, = struct.unpack_from(bo + "I", buf, off); off += 4
    pts = np.frombuffer(buf, dtype=(bo + "f8"), count=2 * n, offset=off).reshape(n, 2).astype(np.float64)
    return pts, off + 16 * n


def _polygon(buf, off):
    bo = "<" if buf[off] == 1 else ">"; off += 1
    t, = struct.unpack_from(bo + "I", buf, off); off += 4
    if t & 0x20000000:                       # EWKB SRID 플래그
        off += 4; t &= 0xFF
    if t != 3:
        raise ValueError("Polygon(3) 이어야 함: %d" % t)
    nr, = struct.unpack_from(bo + "I", buf, off); off += 4
    rings = []
    for _ in range(nr):
        r, off = _ring(buf, off, bo); rings.append(r)
    return rings, off


def decode_wkb(buf):
    """WKB → [폴리곤[링[np(n,2) lon/lat]]]. Polygon(3) · MultiPolygon(6) · SRID 플래그 대응."""
    bo = "<" if buf[0] == 1 else ">"; off = 1
    t, = struct.unpack_from(bo + "I", buf, off); off += 4
    if t & 0x20000000:
        off += 4; t &= 0xFF
    if t == 3:
        rings, _ = _polygon(buf, 0); return [rings]
    if t != 6:
        raise ValueError("Polygon/MultiPolygon 만 지원: %d" % t)
    n, = struct.unpack_from(bo + "I", buf, off); off += 4
    polys = []
    for _ in range(n):
        rings, off = _polygon(buf, off); polys.append(rings)
    return polys


# ───────────────────────── 기하 ─────────────────────────
def signed_area(pts):
    """화면 좌표(x 오른쪽 · y 아래) 신발끈 공식. 양수 = 화면에서 시계방향."""
    x, y = pts[:, 0], pts[:, 1]
    return 0.5 * float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def douglas_peucker(pts, eps):
    """열린 폴리라인 단순화 (반복문 · numpy). pts (n,2) float."""
    n = len(pts)
    if n < 3:
        return pts
    keep = np.zeros(n, dtype=bool); keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        seg = pts[b] - pts[a]
        L = math.hypot(seg[0], seg[1])
        mid = pts[a + 1:b]
        if L == 0:
            d = np.hypot(mid[:, 0] - pts[a][0], mid[:, 1] - pts[a][1])
        else:
            d = np.abs(seg[0] * (mid[:, 1] - pts[a][1]) - seg[1] * (mid[:, 0] - pts[a][0])) / L
        i = int(np.argmax(d))
        if d[i] > eps:
            k = a + 1 + i; keep[k] = True
            stack.append((a, k)); stack.append((k, b))
    return pts[keep]


def simplify_ring(pts_int, eps):
    """닫힌 링(정수 좌표) → 연속 중복 제거 → DP(첫 점 고정, 마지막 점 = 첫 점) → 닫는 점 제거."""
    p = pts_int
    if not np.array_equal(p[0], p[-1]):
        p = np.vstack([p, p[:1]])
    d = np.ones(len(p), dtype=bool); d[1:] = np.any(p[1:] != p[:-1], axis=1)
    p = p[d]
    p = douglas_peucker(p.astype(np.float64), eps)
    p = p[:-1] if len(p) > 1 and np.array_equal(p[0], p[-1]) else p
    return p.astype(np.int64)


# ───────────────────────── 로드 ─────────────────────────
def load_json(p):
    return json.load(io.open(p, encoding="utf-8"))


def load_89():
    with io.open(JOIN89, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(l for l in f if not l.startswith("#")))
    return {r["행정표준코드5"] for r in rows}


def fmt_kb(n):
    return "%.1fKB" % (n / 1024)


# ───────────────────────── 메인 ─────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mockup", action="store_true", help="Docs/mockup/data.js 도 쓴다")
    ap.add_argument("--eps", type=float, default=EPS_PX, help="Douglas-Peucker 허용오차(px)")
    args = ap.parse_args()
    today = datetime.date.today().isoformat()

    topik = load_json(TOPIK)
    T = topik["데이터"]
    cand = {r["code"]: r for r in T["급수후보"]}
    ldong = load_json(LDONG)
    sgg = ldong["시군구"]
    codes89 = load_89()
    df = pq.read_table(PARQ).to_pandas()

    # ── 코드 집합 대조 ──
    set_b = set(df.sggcd.tolist()); set_l = {r["code5"] for r in sgg}; set_c = set(cand)
    set_base = {r["code5"] for r in sgg if r["parent"] == r["code5"]}
    print("■ 코드 집합 대조  경계 %d · ldong %d (기초 %d) · 급수후보 %d · 89곳 %d" % (len(set_b), len(set_l), len(set_base), len(set_c), len(codes89)))
    print("  경계에만 있음      :", sorted(set_b - set_l) or "없음")
    print("  ldong에만 있음     :", sorted(set_l - set_b) or "없음", "(일반구를 둔 시 — 경계는 일반구 단위)")
    print("  급수후보에만 있음  :", sorted(set_c - set_l) or "없음")
    print("  ldong 기초에만 있음:", sorted(set_base - set_c) or "없음")
    miss89 = sorted(codes89 - set_b)
    print("  89곳 경계 누락     :", miss89 or "없음 (89/89)")
    if miss89:
        print("✗ 89곳 중 경계 없는 코드가 있어 중단"); sys.exit(1)
    if set_base - set_c:
        print("✗ 급수후보에 없는 기초지자체가 있어 중단"); sys.exit(1)
    nm_l = {r["code5"]: r["nm"] for r in sgg}
    nm_b = dict(zip(df.sggcd, df.sggnm))
    nm_diff = [c for c in set_b & set_l if nm_l[c].replace(" ", "") != nm_b[c].replace(" ", "")]
    print("  이름 불일치(공백 제외):", ["%s ldong=%s 경계=%s" % (c, nm_l[c], nm_b[c]) for c in nm_diff] or "없음")

    # ── 지역 269행 ──
    regions = []
    for r in sgg:
        base = r["parent"]
        src = cand[base]
        row = {"code": r["code5"], "sido": r["sido"], "nm": r["nm"]}
        for k in COPY_FIELDS:
            row[k] = src[k]
        row["parent"] = None if base == r["code5"] else base
        regions.append(row)
    n_gu = sum(1 for r in regions if r["parent"])

    # ── 요약 재계산 → 원본과 대조 ──
    base_rows = [r for r in regions if not r["parent"]]
    cnt = {lv: {"전체": sum(1 for r in base_rows if r["lv"] == lv),
                "89곳": sum(1 for r in base_rows if r["lv"] == lv and r["is89"])} for lv in LV_ORDER}
    cum = []
    for i, lv in enumerate(LV_ORDER[:4]):
        opened = LV_ORDER[:i + 1]
        cum.append({"사용자급수": lv, "열린lv": " + ".join(opened),
                    "전체": sum(1 for r in base_rows if r["lv"] in opened),
                    "89곳": sum(1 for r in base_rows if r["lv"] in opened and r["is89"])})
    src_sum = T["요약"]
    if cnt != src_sum["급수별곳수"] or cum != src_sum["사용자급수별누적열린곳"]:
        print("✗ 요약 재계산이 analyze_topik_local.json 요약과 다름"); print(cnt); print(src_sum["급수별곳수"]); sys.exit(1)
    summary = {"기초지자체": len(base_rows), "인구감소지역": sum(1 for r in base_rows if r["is89"]),
               "급수별곳수": cnt, "사용자급수별누적열린곳": cum}
    print("■ 요약 재계산 = 원본 일치  기초 %d · 89곳 %d · Lv1~2 %d · Lv3 %d · Lv4 %d · Lv5 %d · 제외 %d · 보류 %d" % (
        summary["기초지자체"], summary["인구감소지역"], *[cnt[lv]["전체"] for lv in LV_ORDER]))

    # ── 경계: 디코드 → 투영 → 정수화 → 단순화 ──
    geoms = {c: decode_wkb(bytes(g)) for c, g in zip(df.sggcd, df.geometry)}
    all_pts = np.vstack([r for polys in geoms.values() for rings in polys for r in rings])
    lon0, lat0 = float(all_pts[:, 0].min()), float(all_pts[:, 1].max())
    lon1, lat1 = float(all_pts[:, 0].max()), float(all_pts[:, 1].min())
    span_x = (lon1 - lon0) * COS_LAT; span_y = (lat0 - lat1)
    scale = min((VIEW_W - 2 * PAD_PX) / span_x, (VIEW_H - 2 * PAD_PX) / span_y)
    off_x = (VIEW_W - span_x * scale) / 2.0; off_y = (VIEW_H - span_y * scale) / 2.0

    def project(pts):
        x = (pts[:, 0] - lon0) * COS_LAT * scale + off_x
        y = (lat0 - pts[:, 1]) * scale + off_y
        return np.rint(np.column_stack([x, y])).astype(np.int64)

    bounds = {}
    n_raw_pts = 0; n_out_pts = 0; n_rings = 0; n_dot = 0; n_holes = 0
    for code in sorted(geoms):
        rings_out = []; seen_dots = set()
        for rings in geoms[code]:
            for i, r in enumerate(rings):
                n_raw_pts += len(r)
                p = simplify_ring(project(r), args.eps)
                distinct = len(np.unique(p, axis=0)) if len(p) else 0
                if distinct < 3 or abs(signed_area(p.astype(np.float64))) < 0.5:
                    if i > 0:
                        continue                                  # 점으로 줄어든 홀은 버림
                    c = np.rint(project(r).mean(axis=0)).astype(np.int64)
                    key = (int(c[0]), int(c[1]))
                    if key in seen_dots:
                        continue
                    seen_dots.add(key); n_dot += 1
                    p = np.array([[c[0], c[1]], [c[0] + DOT_PX, c[1]], [c[0] + DOT_PX // 2, c[1] + DOT_PX]], dtype=np.int64)
                a = signed_area(p.astype(np.float64))
                want_pos = (i == 0)                               # 외곽 = 양수(화면 시계방향) · 홀 = 음수
                if (a > 0) != want_pos:
                    p = p[::-1]
                if i > 0:
                    n_holes += 1
                rings_out.append([[int(x), int(y)] for x, y in p])
                n_out_pts += len(p); n_rings += 1
        bounds[code] = rings_out

    xs = [pt[0] for rs in bounds.values() for r in rs for pt in r]; ys = [pt[1] for rs in bounds.values() for r in rs for pt in r]
    bbox = [min(xs), min(ys), max(xs), max(ys)]
    km_per_px = 111.0 / scale                                    # 위도 1° ≈ 111km · scale = px/°
    print("■ 경계  원꼭짓점 %s → 결과 %s (%.1f%%) · 링 %d (점 링 %d · 홀 %d) · eps %.2fpx ≈ %.2fkm · scale %.2f px/° · bbox %s" % (
        format(n_raw_pts, ","), format(n_out_pts, ","), 100.0 * n_out_pts / n_raw_pts, n_rings, n_dot, n_holes, args.eps, args.eps * km_per_px, scale, bbox))
    assert 0 <= bbox[0] and 0 <= bbox[1] and bbox[2] <= VIEW_W and bbox[3] <= VIEW_H, bbox

    # ── 예시용 실제 값 ──
    ex = cand["12730"]                                           # 구례군
    ex_gu = next(r for r in regions if r["code"] == "41111")     # 수원시 장안구
    ex_b = bounds["11110"]                                       # 종로구
    ex_ul = bounds["47940"]                                      # 울릉군
    ex_hold = next(r for r in regions if r["lv"] == "보류")

    meta = {
        "생성일": today,
        "생성": "python data/AI/build_app_assets.py" + (" --mockup" if args.mockup else ""),
        "산출일": topik["_설명"]["생성일"],
        "입력": {
            "analyze_topik_local.json": {"생성일": topik["_설명"]["생성일"], "급수후보": len(cand), "산출": "analyze_topik_local.py"},
            "ldong_269.json": {"수집일": ldong["pulled_at"], "시군구": ldong["n_sgg"], "기초": ldong["n_base"], "일반구": ldong["n_gu"], "산출": "pull_ldong.py (KorService2/ldongCode2)"},
            "malgil_89_join.csv": {"행수": len(codes89), "출처": "행정안전부 인구감소지역 고시 89곳"},
            "sgg_20260701_light.parquet": {"행수": int(len(df)), "기준일": "2026-07-01", "좌표계": "WGS84 EPSG:4326 · WKB(geoarrow.wkb)"},
        },
        "경계출처": "vuski/admdongkor (GitHub) sgg_20260701_light — 원자료 통계청 SGIS 행정구역경계",
        "라이선스": {
            "경계": "CC BY 4.0 (vuski/admdongkor) · 원자료 통계청 SGIS 공공누리 제1유형",
            "급수·관광정보": "ⓒ한국관광공사 TourAPI 4.0 (areaBasedList2 · ldongCode2) · 한국관광 데이터랩 지역별 방문자수",
            "인구": "행정안전부 주민등록 인구통계 2026년 8월",
            "표시문구": "출처: ⓒ한국관광공사 · 행정안전부 · 통계청 SGIS(경계, vuski/admdongkor CC BY 4.0)",
        },
        "투영": {
            "식": "x = ((lon − lon0)·cos36° )·scale + off_x · y = (lat0 − lat)·scale + off_y · 정수 반올림",
            "lon0": round(lon0, 6), "lat0": round(lat0, 6), "lon1": round(lon1, 6), "lat1": round(lat1, 6),
            "cos36": round(COS_LAT, 6), "scale_px_per_deg": round(scale, 4),
            "off_x": round(off_x, 2), "off_y": round(off_y, 2), "pad_px": PAD_PX, "km_per_px": round(km_per_px, 3),
        },
        "viewBox": "0 0 %d %d" % (VIEW_W, VIEW_H),
        "bbox": bbox,
        "단순화": {
            "방법": "정수 반올림 → 연속 중복 제거 → Douglas-Peucker(numpy) → 폭·높이 1px 이하로 줄어든 섬은 %dpx 삼각형(점 링)" % DOT_PX,
            "허용오차_px": args.eps, "허용오차_km": round(args.eps * km_per_px, 3),
            "원꼭짓점": n_raw_pts, "결과꼭짓점": n_out_pts, "링수": n_rings, "점링수": n_dot, "홀수": n_holes,
            "원격섬": "울릉도·독도 등은 실좌표 그대로 (이동·확대 없음)",
        },
        "규칙상수": T["급수규칙"]["상수"],
        "시군구수": len(regions), "기초지자체수": len(base_rows), "일반구수": n_gu,
        "인구감소지역수": summary["인구감소지역"], "경계수": len(bounds), "급수후보수": len(cand),
    }

    desc = {
        "파일": "build_app_assets.json",
        "무엇": "말길 앱 자산 — 급수 규칙 v2 판정 결과(230곳) + 공사 시군구 269 + 시군구 경계 256 을 viewBox 0 0 1000 1300 정수 좌표로 묶은 한 파일. Flutter 는 rootBundle 로, 목업은 data.js(window.MALGIL) 로 읽는다",
        "생성일": today,
        "생성": meta["생성"],
        "입력": "인간/analyze_topik_local.json (%s) · AI/_raw/ldong_269.json (%s) · AI/_raw/malgil_89_join.csv · AI/_raw/sgg_20260701_light.parquet (2026-07-01 기준 경계 256행)" % (topik["_설명"]["생성일"], ldong["pulled_at"]),
        "정렬": "지역 = ldong_269.json 순서(시도 코드 → 시군구 코드) · 경계 = code 오름차순",
        "행수": "지역 %d · 경계 %d · 급수규칙 상수 4 · 요약 6칸+4행" % (len(regions), len(bounds)),
        "주의": [
            "P-T05 모든 수치에 산출일 병기 — 메타.산출일(%s)을 화면에 함께 표시한다" % meta["산출일"],
            "P-DL01 총량 사용 금지 — share·pb 만 싣고 방문자 절대값(b·c)은 싣지 않는다. 근거 문장도 절대값 표현(1,000명 중 N명)만",
            "일반구(수원시 장안구 41111 등 39행)는 급수를 따로 매기지 않는다 — parent 시(41110)의 lv·수치를 복사했다. 경계는 일반구 단위로만 있으므로 경계 code → 지역.parent → 급수 순으로 찾는다",
            "인천 2026-07 신설 4구(제물포·영종·서해·검단)는 lv=보류 · share 는 1개월치 · pb 는 null",
            "경계는 정수 좌표라 1px ≈ %.2fkm 오차. 지적·행정 목적으로 쓰지 않는다" % km_per_px,
        ],
        "섹션": {
            "메타": {
                "무엇": "이 파일이 무엇으로 만들어졌는지 — 입력의 산출일 · 경계 출처와 라이선스 · 투영식 · 단순화 · 규칙 상수 · 곳수",
                "항목": {
                    "산출일": {"뜻": "급수 판정 수치의 산출일 (앱 화면에 병기할 날짜 · P-T05)", "산식": "analyze_topik_local.json 의 생성일", "범위": "YYYY-MM-DD", "단위": "날짜", "예시": "%s — 지도 하단 「Computed %s」" % (meta["산출일"], meta["산출일"])},
                    "입력": {"뜻": "입력 파일 4개와 각각의 산출일·행수", "산식": "각 파일의 _설명 · 헤더에서 읽음", "범위": "-", "단위": "-", "예시": "ldong_269.json 수집일 %s · 시군구 269" % ldong["pulled_at"]},
                    "라이선스.표시문구": {"뜻": "앱 화면에 붙일 출처 문구", "산식": "고정 문자열", "범위": "-", "단위": "문자열", "예시": meta["라이선스"]["표시문구"]},
                    "투영": {"뜻": "경도·위도 → viewBox 좌표 변환식과 상수", "산식": "x = ((lon−lon0)·cos36°)·scale + off_x · y = (lat0−lat)·scale + off_y", "범위": "lon0~lon1 %.3f~%.3f · lat1~lat0 %.3f~%.3f" % (lon0, lon1, lat1, lat0), "단위": "도 · px", "예시": "scale %.2f px/° → 1px ≈ %.2fkm · off_y %.1f (세로로 가운데 맞춤)" % (scale, km_per_px, off_y)},
                    "viewBox": {"뜻": "SVG/CustomPainter 좌표계 크기", "산식": "고정", "범위": "-", "단위": "px", "예시": meta["viewBox"]},
                    "bbox": {"뜻": "실제 좌표가 차지하는 [xmin, ymin, xmax, ymax]", "산식": "경계 전체 꼭짓점의 최소·최대", "범위": "0~1000 · 0~1300", "단위": "px", "예시": "%s — 가로는 꽉 차고 세로는 위아래 여백" % bbox},
                    "단순화": {"뜻": "꼭짓점을 줄인 방법과 허용오차·개수", "산식": "Douglas-Peucker 허용오차 %.2fpx" % args.eps, "범위": "-", "단위": "px · km · 개", "예시": "원꼭짓점 %s → %s · 점 링 %d개(폭·높이 1px 이하 섬)" % (format(n_raw_pts, ","), format(n_out_pts, ","), n_dot)},
                    "규칙상수": {"뜻": "급수 규칙 v2 상수 (급수규칙 섹션과 동일 · 화면 문구용 복사본)", "산식": "analyze_topik_local.json 급수규칙.상수", "범위": "-", "단위": "건 · % · % · 백분위", "예시": "KOR_T %d · SHARE_T %.1f · OLD65_T %.0f · PB_T %d" % (T["급수규칙"]["상수"]["KOR_T"], T["급수규칙"]["상수"]["SHARE_T"], T["급수규칙"]["상수"]["OLD65_T"], T["급수규칙"]["상수"]["PB_T"])},
                    "시군구수 · 기초지자체수 · 일반구수 · 인구감소지역수 · 경계수": {"뜻": "각 집합의 크기", "산식": "count", "범위": "-", "단위": "곳", "예시": "시군구 %d = 기초 %d + 일반구 %d · 경계 %d = 269 − 일반구를 둔 시 13" % (len(regions), len(base_rows), n_gu, len(bounds))},
                },
            },
            "급수규칙": dict(topik["_설명"]["섹션"]["급수규칙"], **{"출처": "analyze_topik_local.json 급수규칙 섹션을 그대로 복사"}),
            "요약": dict(topik["_설명"]["섹션"]["요약"], **{"출처": "지역 행에서 재계산해 analyze_topik_local.json 요약과 일치를 확인한 값"}),
            "지역": {
                "무엇": "공사 ldongCode2 시군구 %d행 전부 (기초 %d + 일반구 %d). 앱의 드롭다운·시트·지도 색이 이 행을 본다" % (len(regions), len(base_rows), n_gu),
                "정렬": "ldong_269.json 순서 (시도 코드 → 시군구 코드)",
                "행수": len(regions),
                "항목": {
                    "code": {"뜻": "행정표준코드 5자리 (공사 ldongCode2 신코드 · 경계 키와 같은 체계)", "산식": "원자료", "범위": "5자리 숫자 문자열", "단위": "코드", "예시": "12730 = 전남광주통합특별시 구례군 · 41111 = 경기도 수원시 장안구(일반구)"},
                    "sido": {"뜻": "시도명 (ldongCode2 기준 16개)", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": ex["sido"]},
                    "nm": {"뜻": "시군구명 (일반구는 「시 이름 + 공백 + 구 이름」)", "산식": "원자료", "범위": "-", "단위": "문자열", "예시": "%s · %s" % (ex["nm"], ex_gu["nm"])},
                    "구분": {"뜻": "군 · 자치구 · 시 (일반구 행은 parent 시의 구분 = 시)", "산식": "이름 접미사", "범위": "군/자치구/시", "단위": "문자열", "예시": "%s %s = %s · 대구 군위군 = 군" % (ex["sido"], ex["nm"], ex["구분"])},
                    "lv": {"뜻": "급수 맵 칸 (급수 규칙 v2). 일반구는 parent 값 복사", "산식": "급수규칙.순서대로 첫 조건", "범위": "Lv1~2 · Lv3 · Lv4 · Lv5 · 제외 · 보류", "단위": "구분", "예시": "%s %s · %s %s(%s 복사)" % (ex["nm"], ex["lv"], ex_gu["nm"], ex_gu["lv"], ex_gu["parent"])},
                    "근거_ko": {"뜻": "그 급수인 이유 — 절대값 문장만 (백분율·백분위 없음)", "산식": "lv 분기 서술 (analyze_topik_local.py)", "범위": "-", "단위": "문자열", "예시": "%s — 「%s」" % (ex["nm"], ex["근거_ko"])},
                    "근거_en": {"뜻": "근거_ko 의 영문 (앱 기본 표시)", "산식": "lv 분기 서술", "범위": "-", "단위": "문자열", "예시": "%s — \"%s\"" % (ex["nm"], ex["근거_en"])},
                    "share": {"뜻": "외국인 방문 비중 — 낮을수록 그 동네의 기본 언어가 한국어", "산식": "외국인 / (외지인 + 외국인) × 100 · 12개월 누계 (보류 행은 1개월)", "범위": "0~100", "단위": "%", "예시": "%s %.3f%% — 방문자 1,000명 중 외국인 %d명" % (ex["nm"], ex["share"], round(ex["share"] * 10))},
                    "pb": {"뜻": "내국인 방문 규모 백분위 (시·군의 Lv3 판정축)", "산식": "완전월 기초지자체 중 외지인 방문지표 백분위", "범위": "0~100 또는 null(보류)", "단위": "백분위", "예시": "%s %s · %s null" % (ex["nm"], ex["pb"], ex_hold["nm"])},
                    "kor": {"뜻": "국문 관광자원 두께 (쇼핑 제외)", "산식": "관광지+문화시설+축제+음식점 건수", "범위": "0 이상", "단위": "건", "예시": "%s %d건" % (ex["nm"], ex["kor"])},
                    "e65": {"뜻": "65세 이상 인구 비율 (군의 Lv5 판정축)", "산식": "65세 이상 / 총인구 × 100", "범위": "0~100", "단위": "%", "예시": "%s %.1f%% — 주민 10명 중 %d명" % (ex["nm"], ex["e65"], round(ex["e65"] / 10))},
                    "pop": {"뜻": "주민등록 총인구 (2026년 8월)", "산식": "원자료", "범위": "0 이상", "단위": "명", "예시": "%s %s명" % (ex["nm"], format(ex["pop"], ","))},
                    "is89": {"뜻": "행안부 인구감소지역 89곳인가", "산식": "malgil_89_join.csv 코드 대조", "범위": "true / false", "단위": "불리언", "예시": "%s %s · 대전 중구 false" % (ex["nm"], str(ex["is89"]).lower())},
                    "months": {"뜻": "방문자 집계 개월 수 (12 미만 = 보류)", "산식": "원자료 집계", "범위": "1~12", "단위": "개월", "예시": "%s %d · %s %d" % (ex["nm"], ex["months"], ex_hold["nm"], ex_hold["months"])},
                    "parent": {"뜻": "일반구가 속한 시의 code. 기초지자체 행은 null. 경계는 일반구 code 로 있으므로 그 폴리곤의 색은 parent 행의 lv 로 칠한다", "산식": "ldong_269.json 의 parent (code5 와 같으면 null)", "범위": "5자리 코드 또는 null", "단위": "코드", "예시": "%s %s → parent %s (수원시 행의 lv·수치를 복사) · %s → null" % (ex_gu["code"], ex_gu["nm"], ex_gu["parent"], ex["code"])},
                },
            },
            "경계": {
                "무엇": "시군구 %d곳의 폴리곤 링 — {code: [[[x,y],…], …]}. 링마다 첫 점으로 되돌아가는 닫는 점은 없다(그릴 때 Z 로 닫는다)" % len(bounds),
                "정렬": "code 오름차순 · 링은 원본 폴리곤 순서 (본토·큰 섬이 먼저라는 보장은 없음)",
                "행수": len(bounds),
                "항목": {
                    "code": {"뜻": "행정표준코드 5자리 (지역.code 또는 지역.parent 와 잇는다)", "산식": "parquet sggcd", "범위": "5자리 숫자 문자열", "단위": "코드", "예시": "11110 종로구 — 링 %d개 · 꼭짓점 %d개 · 첫 점 %s" % (len(ex_b), sum(len(r) for r in ex_b), ex_b[0][0])},
                    "링": {"뜻": "닫힌 폴리곤 하나 = [x,y] 정수 배열. 외곽선은 화면 시계방향(신발끈 면적 양수) · 홀은 반시계(음수) — fill-rule nonzero 로 그리면 홀이 비워진다", "산식": "WKB 링 → 투영 → 정수 반올림 → DP 단순화 → 방향 정규화", "범위": "x 0~%d · y 0~%d · 점 3개 이상" % (VIEW_W, VIEW_H), "단위": "px", "예시": "47940 울릉군 — 링 %d개(울릉도 %d점 + 독도 등 점 링) · 독도는 실좌표라 화면 오른쪽 끝 x≈%d" % (len(ex_ul), max(len(r) for r in ex_ul), max(pt[0] for r in ex_ul for pt in r))},
                },
            },
        },
    }

    data = {"메타": meta, "급수규칙": T["급수규칙"], "요약": summary, "지역": regions, "경계": bounds}
    head = json.dumps(desc, ensure_ascii=False, indent=1)
    body = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    text = '{\n"_설명": ' + head + ',\n"데이터": ' + body + "\n}\n"
    json.loads(text)                                              # 형식 검증

    os.makedirs(os.path.dirname(APP_ASSET), exist_ok=True)
    with io.open(APP_ASSET, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    size = os.path.getsize(APP_ASSET)
    print("■ 출력  %s  %s (%s 바이트) · 지역 %d · 경계 %d" % (os.path.realpath(APP_ASSET), fmt_kb(size), format(size, ","), len(regions), len(bounds)))
    if size > 1024 * 1024:
        print("✗ 1MB 초과 — --eps 를 키우세요"); sys.exit(1)
    if args.mockup:
        with io.open(MOCKUP_JS, "w", encoding="utf-8", newline="\n") as f:
            f.write("/* build_app_assets.py --mockup 산출 · 생성일 %s · 손으로 고치지 않는다 */\nwindow.MALGIL = " % today + text.rstrip("\n") + ";\n")
        print("■ 목업  %s  %s" % (MOCKUP_JS, fmt_kb(os.path.getsize(MOCKUP_JS))))


if __name__ == "__main__":
    main()
