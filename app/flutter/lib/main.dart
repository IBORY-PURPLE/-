// 진입점 — runApp 전에 자산(rootBundle) 로드 + AppState 복원.
// 정적 로딩 셸 제거는 web/index.html 이 `flutter-first-frame` 이벤트로 처리한다.
// URL 은 해시(#/) 가 아니라 경로(/map · /?demo=1)로 — 워커의 SPA 폴백이 index.html 을 내므로 딥링크가 된다.
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'data/assets.dart';
import 'state/app_state.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final (assets, appState) = await (loadAssets(), AppState.restore()).wait;
  runApp(MalgilApp(assets: assets, appState: appState));
}
