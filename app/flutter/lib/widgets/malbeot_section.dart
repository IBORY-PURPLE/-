// 동네 말벗 섹션 — PRD F7 · 기획서 §5-3. 지역 시트·장소 상세의 「Local companion」 카드 자리에만 붙는다 (별도 탭·라우트 없음 — P-O02).
//  세션 2종(제출본): S2 「Market regulars alley」 Lv3 · S1 「Driver's diner table」 Lv4.
//  노출은 지역 급수로: Lv1~2·Lv3 → S2 · Lv4·Lv5 → S2 + S1 · 보류·제외·미상 → 기본 카드(현행 recruiting + kctg)만.
//  급수 게이트: 사용자 급수 < 세션 급수면 CTA 를 실제로 비활성(onPressed: null) + 「Opens at LvN — keep exploring; the map still works」.
//  상태는 전부 recruiting (P-O01 허위 슬롯 금지 — 더미 프로필·날짜·슬롯 없음). 관심은 AppState.interests 에 기기 저장만 (서버 전송·이메일 없음).
//  L3 안전망(kctg.or.kr 새 탭)은 항상, 필수 고지문(한국어 원문 · P-T03 각주와 같은 bodySmall muted)은 세션이 보일 때 카드 하단.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/assets.dart';
import '../i18n/strings_en.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'level_chip.dart';

/// 세션 정의 (기획서 §5-3 (2) 표) — 제출본 2종만. S3~S5 는 발전계획이라 넣지 않는다.
class MalbeotSession {
  const MalbeotSession({required this.id, required this.level, required this.title, required this.body});

  final String id; // AppState.interests 값 · Key 접미 ('s1' · 's2')
  final int level; // 세션 급수 — 사용자 급수 ≥ 이 값이면 CTA 활성
  final String title;
  final String body;

  static const MalbeotSession s2 = MalbeotSession(id: 's2', level: 3, title: S.sessionS2Title, body: S.sessionS2Body);
  static const MalbeotSession s1 = MalbeotSession(id: 's1', level: 4, title: S.sessionS1Title, body: S.sessionS1Body);

  /// 지역 급수 → 보일 세션. Lv1~2·Lv3 → [S2] · Lv4·Lv5 → [S2, S1] · 보류·제외·미상(null) → [] (기본 카드)
  static List<MalbeotSession> forRegion(Region? r) {
    if (r == null) return const [];
    final n = lvNum[r.lv];
    if (n == null) return const [];
    return n >= 4 ? const [s2, s1] : const [s2];
  }
}

class MalbeotSection extends StatelessWidget {
  const MalbeotSection({
    super.key,
    required this.region,
    required this.userLevel,
    required this.appState,
    this.compact = false,
    this.onOpenKctg,
  });

  final Region? region; // null(급수표에 없는 코드) → 기본 카드
  final int userLevel; // 사용자 급수 2..5
  final AppState appState;
  final bool compact; // 장소 상세용: 긴 소개문 + 세션 설명 줄 생략(정원 「Max 5」는 PRD 필수라 유지) + 「Licensed interpreter booking」 라벨
  final VoidCallback? onOpenKctg; // 기본 url_launcher 새 탭 (테스트 주입용)

  static Future<void> openKctg() async {
    try {
      await launchUrl(Uri.parse(S.kctgUrl), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (e) {
      debugPrint('MalbeotSection: launchUrl failed ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = MalbeotSession.forRegion(region);
    final muted = MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant);
    final small = MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant);

    return Card.outlined(
      key: const Key('malbeot-section'),
      color: MalgilColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MalgilShape.cornerMedium),
        side: const BorderSide(color: MalgilColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(S.localCompanion, style: MalgilType.titleSmall),
              const SizedBox(height: 4),
              Text(compact ? S.localCompanionBodyLong : S.localCompanionBody, style: muted),
              for (final s in sessions) ...[
                const SizedBox(height: 12),
                _SessionCard(
                  session: s,
                  enabled: userLevel >= s.level,
                  interested: appState.hasInterest(region!.code, s.id),
                  compact: compact,
                  onToggle: () => appState.toggleInterest(region!.code, s.id),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('open-kctg'),
                  onPressed: onOpenKctg ?? openKctg,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(compact ? S.licensedInterpreter : S.openKctg),
                ),
              ),
              if (sessions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${S.malbeotNoticeKo}\n${S.malbeotNoticeEn}', key: const Key('malbeot-notice'), style: small),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 세션 카드 한 장 — 제목 · LevelChip(세션 급수) · 한 줄 설명 · 「Max 5」 · 상태 recruiting · CTA(게이트)
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.enabled,
    required this.interested,
    required this.compact,
    required this.onToggle,
  });

  final MalbeotSession session;
  final bool enabled; // 사용자 급수 ≥ 세션 급수
  final bool interested; // AppState.interests 에 등록됨
  final bool compact; // 한 줄 설명만 생략 — 정원 「Max 5」·상태·CTA 는 항상
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final muted = MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant);
    final small = MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant);
    final id = session.id;
    final label = Text(interested ? S.interestNoted : S.interestCta, textAlign: TextAlign.center);
    return Container(
      key: Key('session-$id'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MalgilColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MalgilShape.cornerMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(session.title, style: MalgilType.titleSmall)),
              const SizedBox(width: 8),
              LevelChip.ofLevel(session.level),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(session.body, style: muted),
          ],
          // 정원 표기는 PRD F7 필수(「최대 5명 — 이야기가 흐르는 크기」) — compact 에서도 유지
          const SizedBox(height: 4),
          Text(S.sessionMax5, style: small),
          const SizedBox(height: 4),
          Text(S.sessionRecruiting, key: Key('status-$id'), style: MalgilType.labelMedium.copyWith(color: MalgilColors.onSurfaceVariant, letterSpacing: 0)),
          const SizedBox(height: 8),
          if (interested)
            FilledButton.tonalIcon(
              key: Key('interest-$id'),
              onPressed: enabled ? onToggle : null,
              icon: const Icon(Icons.check, size: 18),
              label: label,
            )
          else
            FilledButton.tonal(key: Key('interest-$id'), onPressed: enabled ? onToggle : null, child: label),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(S.sessionOpensAt(lvLabel[session.level] ?? ''), key: Key('gate-$id'), style: small),
            ),
        ],
      ),
    );
  }
}
