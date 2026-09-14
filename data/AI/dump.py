# -*- coding: utf-8 -*-
"""
말길 · TourAPI 4.0 areaBasedList2 전량 덤프  (KorService2 국문 + EngService2 영문)

  출력  _raw/dump.json  {"dumped_at": "YYYY-MM-DD",
                         "KorService2": {"total", "fetched", "items": [...]},
                         "EngService2": {"total", "fetched", "items": [...]}}
        items 는 slim() 으로 10개 필드만 남긴다
        (contentid · contenttypeid · title · addr1 · lDongRegnCd · lDongSignguCd ·
         areacode · sigungucode · lclsSystm1 · lclsSystm2)
  호출  1,000건/페이지 → 국문 약 50회 + 영문 약 16회 ≈ 65회 (한도 1,000회/일 대비 미미)
  실행  python data/AI/dump.py

  ★ EngService2 를 함께 덤프하는 이유와 한계
      analyze_89_culture.py 가 아직 영문 등재 건수(eng_cul)를 쓴다. 그래서 유지한다.
      ⛔ 급수 판정(analyze_topik_local.py)에는 영문 카탈로그를 쓰지 않는다 — 기획서 P-M04.
         「영문 등재 여부」로 장소의 열림/닫힘을 판정하면 중국어·일본어·베트남어권 방문자를
         전부 영어권으로 치환하게 된다. 그 지표가 재는 값은 영어 번역 진척도이지
         「한국어가 필요한 정도」가 아니다.

  인증키  프로젝트 루트 .env 의 Api_Key_Decoding (pull_visitor.py 의 load_key 와 같은 방식).
          환경변수 TOUR_API_KEY 는 대체 경로. 값은 절대 출력하지 않는다.

  기록  2026-09-03 첫 덤프 · 2026-09-14 재덤프(산출일 갱신 P-T05 · 인천 신코드 확인 · kor 최신화)
"""
import io, os, sys, re, json, time, datetime, urllib.request, urllib.parse

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))          # data/AI
RAW = os.path.join(HERE, "_raw")                          # 원본·중간 파일 (사람이 안 읽음)
OUT = os.path.join(os.path.dirname(HERE), "인간")          # 사람이 읽는 산출물
ROOT = os.path.dirname(os.path.dirname(HERE))             # 프로젝트 루트 (.env)
BASE = "https://apis.data.go.kr/B551011"
ROWS = 1000
CALLS = 0


def load_key():
    """프로젝트 루트 .env 에서 인증키를 읽는다 (.env 는 .gitignore 대상)."""
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
        raise SystemExit(".env 에 Api_Key_Decoding 이 없습니다 (또는 TOUR_API_KEY 환경변수)")
    return key


KEY = load_key()


def fetch(svc, page, rows=ROWS):
    global CALLS
    q = {"MobileOS": "ETC", "MobileApp": "malgil", "_type": "json",
         "numOfRows": rows, "pageNo": page}
    url = "%s/%s/areaBasedList2?serviceKey=%s&%s" % (
        BASE, svc, urllib.parse.quote(KEY, safe=""), urllib.parse.urlencode(q))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    CALLS += 1
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read().decode("utf-8", "replace")
    if not raw.lstrip().startswith("{"):
        m = re.search(r"<(?:returnAuthMsg|errMsg|resultMsg)>(.*?)</", raw)
        raise RuntimeError(m.group(1) if m else raw[:200])
    j = json.loads(raw)
    if "response" not in j:                      # TSD §4-4 — 파라미터 오류는 래퍼 없이 온다
        raise RuntimeError("%s %s" % (j.get("resultCode"), j.get("resultMsg")))
    b = j["response"]["body"]
    it = b.get("items") or {}
    arr = it.get("item", []) if isinstance(it, dict) else []
    if isinstance(arr, dict):
        arr = [arr]
    return int(b.get("totalCount", 0) or 0), arr


def collect(svc):
    total, first = fetch(svc, 1)
    out = list(first)
    pages = (total + ROWS - 1) // ROWS
    print("%s: total=%d pages=%d" % (svc, total, pages))
    for p in range(2, pages + 1):
        for a in range(4):
            try:
                _, arr = fetch(svc, p)
                out.extend(arr)
                break
            except Exception as e:
                print("  p%d try%d fail %s" % (p, a, e))
                time.sleep(2)
        time.sleep(0.1)
    print("%s: got %d" % (svc, len(out)))
    return total, out


FIELDS = ("contentid", "contenttypeid", "title", "addr1", "lDongRegnCd", "lDongSignguCd",
          "areacode", "sigungucode", "lclsSystm1", "lclsSystm2")


def slim(r):
    return {k: r.get(k, "") for k in FIELDS}


def main():
    res = {"dumped_at": datetime.date.today().isoformat(), "operation": "areaBasedList2"}
    for svc in ("KorService2", "EngService2"):
        t, rows = collect(svc)
        res[svc] = {"total": t, "fetched": len(rows), "items": [slim(r) for r in rows]}
    p = os.path.join(RAW, "dump.json")
    json.dump(res, open(p, "w", encoding="utf-8"), ensure_ascii=False)
    print("DONE", {k: (v["total"], v["fetched"]) for k, v in res.items() if isinstance(v, dict)},
          "· %d회 호출 → %s" % (CALLS, p))


if __name__ == "__main__":
    main()
