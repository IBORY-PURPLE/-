// 표시용 포맷 — 워커 fetchedAt(ISO 8601 UTC) → 사용자 로컬 시각 문자열 (P-T05: 모든 실시간 수치에 fetched 시각 병기)
String _two(int n) => n.toString().padLeft(2, '0');

/// `2026-09-14T09:33:00.000Z` → 로컬 `2026-09-14 18:33` (timeOnly 면 `18:33`). 파싱 실패면 원문 그대로.
String formatFetchedAt(String? iso, {bool timeOnly = false}) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final hm = '${_two(d.hour)}:${_two(d.minute)}';
  return timeOnly ? hm : '${d.year}-${_two(d.month)}-${_two(d.day)} $hm';
}

/// 「N min ago」 — 직전 성공 응답 시각과 지금의 차이(분, 최소 0)
int minutesSince(DateTime then, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(then).inMinutes;
  return diff < 0 ? 0 : diff;
}

/// `<br>` `<br/>` → [replacement]. 공사 overview·opentimefood 에 섞여 오는 유일한 태그 (04_place.html 과 같은 처리)
String stripBr(String? s, {String replacement = ' '}) =>
    (s ?? '').replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), replacement).trim();
