// /place/:id — Docs/mockup/04_place.html 과 1:1.
//  히어로 KtoImage(16:9 · contain 기본 · Type3 면 캡션 「· 변경금지(Type3)」 · 이미지 없으면 메뉴 텍스트 히어로 — PRD F4 · 회귀 #4) · 제목 · 주소 ·
//  「This region: Lv」 LevelChip + why ▸(/map) · 「Korean you'll use here」(음식점 메뉴 칩) · About(overview · Read more) ·
//  운영 정보(있는 것만) · 동네 말벗 섹션(MalbeotSection compact — Local companion 카드 자리 · kctg.or.kr) · 「I visited here」 체크 · 푸터
//  ★ ApiClient.place(id) 1콜 → contenttypeid 39 일 때만 placeIntro(id,'39') 1콜 추가. 렌더 시점 호출 · 저장 없음.
//  ★ 지역 급수는 자산에서: lDongRegnCd(2, 세종은 5) + lDongSignguCd(3) → code → sourceRegionFor (일반구면 parent 시)
//  상태: 로딩 · 404 not_found 「This place is no longer listed」 · quota 배너(일일 한도만 — 워커 rate_limited 429 는 error + Retry) · error + Retry
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../data/api.dart';
import '../data/assets.dart';
import '../data/format.dart';
import '../i18n/strings_en.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kto_image.dart';
import '../widgets/level_chip.dart';
import '../widgets/malbeot_section.dart';
import '../widgets/region_sheet.dart' show RegionSheet;
import '../widgets/state_views.dart';

/// 음식점 유형 코드 — intro 를 추가 호출하는 유일한 유형
const String foodTypeId = '39';

/// firstmenu · treatmenu → 메뉴 구절 (04_place.html 과 같은 규칙)
///  「/」「,」「·」로 쪼개고 끝의 「등」 제거, 공백 정리, 20자 미만만. `<br>` 은 구분자로 취급.
List<String> menuPhrases(String? firstmenu, String? treatmenu) {
  final joined = [firstmenu, treatmenu].where((s) => s != null && s.trim().isNotEmpty).join(' / ');
  return stripBr(joined, replacement: ' / ')
      .split(RegExp(r'[/,·]'))
      .map((s) => s.trim().replaceAll(RegExp(r'\s*등$'), '').trim())
      .where((s) => s.isNotEmpty && s.length < 20)
      .toList();
}

/// detailCommon2 의 lDongRegnCd + lDongSignguCd → 행정표준코드 5자리. 세종은 lDongRegnCd 가 5자리로 온다.
String? regionCodeOf(Map<String, dynamic> common) {
  final regn = (common['lDongRegnCd'] ?? '').toString().trim();
  final sgg = (common['lDongSignguCd'] ?? '').toString().trim();
  if (regn.length == 5) return regn;
  if (regn.length == 2 && sgg.length == 3) return '$regn$sgg';
  return null;
}

/// 운영 정보 (detailIntro2 · 39) — 있는 것만 (라벨, 값) 순서대로
List<(String, String)> operatingInfo(Map<String, dynamic>? intro) {
  if (intro == null) return const [];
  String v(String k) => stripBr(intro[k]?.toString(), replacement: '\n');
  final out = <(String, String)>[];
  for (final (k, label) in const [
    ('opentimefood', S.hours),
    ('restdatefood', S.closed),
    ('parkingfood', S.parking),
    ('infocenterfood', S.phone),
    ('reservationfood', S.reservation),
  ]) {
    final s = v(k);
    if (s.isNotEmpty) out.add((label, s));
  }
  return out;
}

class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key, required this.id, this.apiClient, this.today, this.onOpenKctg});
  final String id; // contentid
  final ApiClient? apiClient; // 테스트 주입용
  final String? today; // yyyy-mm-dd (테스트 주입용)
  final VoidCallback? onOpenKctg;

  static const double maxWidth = 560;

  @override
  State<PlaceScreen> createState() => PlaceScreenState();
}

class PlaceScreenState extends State<PlaceScreen> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  bool _loading = true;
  ApiResult? _common; // detailCommon2 응답
  ApiResult? _intro; // detailIntro2 응답 (39 일 때만)
  bool _aboutOpen = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _intro = null;
    });
    final c = await _api.place(widget.id);
    ApiResult? i;
    if (c is ApiOk && c.items.isNotEmpty && (c.items.first['contenttypeid'] ?? '').toString() == foodTypeId) {
      i = await _api.placeIntro(widget.id, foodTypeId);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _common = c;
      _intro = i;
    });
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/map');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final a = scope.assets;
    final appState = scope.appState;
    final c = _common;
    final i = _intro;

    Widget body;
    if (_loading) {
      body = StateViews.loading(rows: 2);
    } else if (c is ApiError && c.kind == 'not_found') {
      body = StateViews.empty(
        title: S.placeNotListed,
        description: S.placeNotListedBody,
        actionLabel: S.back,
        onAction: () => _back(context),
      );
    } else if (c is ApiQuota && c.isDailyQuota) {
      body = StateViews.quota(asOf: a.meta.asOf);
    } else if (c is ApiError || c is! ApiOk || c.items.isEmpty) {
      // rate_limited(429 · 워커 IP 제한)도 여기로 — 한도 배너가 아니라 Retry
      body = StateViews.error(onRetry: reload);
    } else {
      final common = c.items.first;
      final introItem = (i is ApiOk && i.items.isNotEmpty) ? i.items.first : null;
      final code = regionCodeOf(common);
      final region = code == null ? null : (a.sourceRegionFor(code) ?? a.byCode[code]);
      final visitCode = region?.code ?? code;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (i is ApiQuota && i.isDailyQuota) StateViews.quota(),
          if (i is ApiQuota && !i.isDailyQuota) StateViews.error(onRetry: reload),
          _PlaceBody(
            common: common,
            intro: introItem,
            region: region,
            visitCode: visitCode,
            appState: appState,
            today: widget.today ?? RegionSheet.todayString(),
            aboutOpen: _aboutOpen,
            onToggleAbout: () => setState(() => _aboutOpen = !_aboutOpen),
            onWhy: () => context.go('/map'),
            onOpenKctg: widget.onOpenKctg,
            footer: S.placeFooter(formatFetchedAt(c.fetchedAt), withIntro: introItem != null),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _back(context), tooltip: S.back),
        title: const Text(S.placeTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PlaceScreen.maxWidth),
          child: ListView(key: const Key('place-scroll'), children: [body]),
        ),
      ),
    );
  }
}

class _PlaceBody extends StatelessWidget {
  const _PlaceBody({
    required this.common,
    required this.intro,
    required this.region,
    required this.visitCode,
    required this.appState,
    required this.today,
    required this.aboutOpen,
    required this.onToggleAbout,
    required this.onWhy,
    required this.onOpenKctg,
    required this.footer,
  });

  final Map<String, dynamic> common;
  final Map<String, dynamic>? intro;
  final Region? region;
  final String? visitCode;
  final AppState appState;
  final String today;
  final bool aboutOpen;
  final VoidCallback onToggleAbout;
  final VoidCallback onWhy;
  final VoidCallback? onOpenKctg; // null 이면 MalbeotSection 기본(url_launcher 새 탭)
  final String footer;

  String _s(String k) => (common[k] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final muted = MalgilType.bodyMedium.copyWith(color: MalgilColors.onSurfaceVariant);
    final small = MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant);
    final img1 = _s('firstimage');
    final img2 = _s('firstimage2');
    final img = img1.isNotEmpty ? img1 : img2;
    final cpy = _s('cpyrhtDivCd');
    final addr = [_s('addr1'), _s('addr2')].where((s) => s.isNotEmpty).join(' ');
    final menu = menuPhrases(intro?['firstmenu']?.toString(), intro?['treatmenu']?.toString());
    final overview = stripBr(_s('overview'));
    final info = operatingInfo(intro);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 이미지가 없어도 히어로 자리는 유지 — 메뉴 텍스트(firstmenu · treatmenu 앞 3개), 메뉴도 없으면 제목 (PRD F4 · TSD §9 MenuTextHero)
        KtoImage(
          key: const Key('hero'),
          url: img.isEmpty ? null : img,
          cpyrhtDivCd: cpy,
          label: menu.isNotEmpty ? menu.take(3).join(' / ') : _s('title'),
          aspectRatio: 16 / 9,
          borderRadius: 0,
          captionSmall: false,
          captionSuffix: KtoImage.heroCaptionSuffix(cpy),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_s('title'), key: const Key('place-title'), style: MalgilType.headlineSmall),
              if (addr.isNotEmpty) Text(addr, style: muted),
              const SizedBox(height: 12),
              if (region != null)
                Row(
                  children: [
                    KeyedSubtree(key: const Key('region-chip'), child: _regionChip(region!)),
                    TextButton(key: const Key('why'), onPressed: onWhy, child: const Text(S.why)),
                  ],
                ),
              if (menu.isNotEmpty) ...[
                const SizedBox(height: 12),
                _KoreanHereCard(menu: menu),
              ],
              const SizedBox(height: 12),
              _AboutCard(overview: overview, open: aboutOpen, onToggle: onToggleAbout),
              if (info.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InfoCard(info: info),
              ],
              const SizedBox(height: 12),
              MalbeotSection(
                region: region,
                userLevel: appState.level ?? demoLevel,
                appState: appState,
                compact: true,
                onOpenKctg: onOpenKctg,
              ),
              const SizedBox(height: 4),
              if (visitCode != null) _VisitedTile(appState: appState, code: visitCode!, today: today),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: MalgilColors.outlineVariant))),
          child: Text(footer, key: const Key('place-footer'), style: small.copyWith(fontSize: 11, height: 16 / 11)),
        ),
      ],
    );
  }

  /// 「This region: Lv3」 — 보류·제외도 같은 접두어로 (급수는 지역 단위)
  Widget _regionChip(Region r) {
    if (r.lv == lvHold) return LevelChip(kind: LevelChipKind.hold, label: S.thisRegion(S.chipHold));
    if (r.lv == lvExcluded) return LevelChip(kind: LevelChipKind.excluded, label: S.thisRegion(S.chipExcluded));
    return LevelChip.ofLevel(lvNum[r.lv] ?? 5, label: S.thisRegion(r.lv));
  }
}

/// 「Korean you'll use here」 — Card.elevated · 메뉴 칩(.phrase) · Try: 「{첫 메뉴} 하나 주세요」 · 「이거 얼마예요?」
class _KoreanHereCard extends StatelessWidget {
  const _KoreanHereCard({required this.menu});
  final List<String> menu;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('korean-card'),
        elevation: 1,
        color: MalgilColors.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(S.koreanHereTitle, style: MalgilType.titleMedium),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 12),
                child: Text(S.koreanHereSub, style: MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final m in menu) _Phrase(text: m)],
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: S.tryPrefix),
                  TextSpan(text: S.tryOrder(menu.first), style: const TextStyle(color: MalgilColors.onSurface)),
                  const TextSpan(text: ' · '),
                  const TextSpan(text: S.tryPrice, style: TextStyle(color: MalgilColors.onSurface)),
                ]),
                key: const Key('try-line'),
                style: MalgilType.bodySmall.copyWith(color: MalgilColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
}

/// .phrase — primary-container 36px 칩
class _Phrase extends StatelessWidget {
  const _Phrase({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: MalgilColors.primaryContainer, borderRadius: BorderRadius.circular(MalgilShape.cornerSmall)),
        child: Text(text, style: const TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500, color: MalgilColors.onPrimaryContainer)),
      );
}

/// About — overview(한국어) · 접힘 4줄 · Read more / Show less
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.overview, required this.open, required this.onToggle});
  final String overview;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('about-card'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(S.about, style: MalgilType.titleMedium),
              const SizedBox(height: 4),
              Text(
                overview,
                key: const Key('overview'),
                style: MalgilType.bodyMedium,
                maxLines: open ? null : 4,
                overflow: open ? TextOverflow.visible : TextOverflow.fade,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(key: const Key('read-more'), onPressed: onToggle, child: Text(open ? S.showLess : S.readMore)),
              ),
            ],
          ),
        ),
      );
}

/// 운영 정보 — Card.outlined · dt/dd (Hours · Closed · Parking · Phone · Reservation 중 있는 것만)
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.info});
  final List<(String, String)> info;

  @override
  Widget build(BuildContext context) => Card.outlined(
        key: const Key('info-card'),
        color: MalgilColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MalgilShape.cornerMedium),
          side: const BorderSide(color: MalgilColors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in info) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(label, style: MalgilType.labelMedium.copyWith(color: MalgilColors.onSurfaceVariant, letterSpacing: 0)),
                ),
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(value, style: MalgilType.bodyMedium)),
              ],
            ],
          ),
        ),
      );
}

/// 「I visited here (self-reported, stays on this device)」 → AppState.addVisit(지역 code, 오늘)
class _VisitedTile extends StatelessWidget {
  const _VisitedTile({required this.appState, required this.code, required this.today});
  final AppState appState;
  final String code;
  final String today;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final visited = (appState.visits[code] ?? const <String>[]).contains(today);
          return CheckboxListTile(
            key: const Key('visited-here'),
            value: visited,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(S.visitedHere, style: MalgilType.bodyMedium),
            onChanged: visited ? null : (_) => appState.addVisit(code, today),
          );
        },
      );
}
