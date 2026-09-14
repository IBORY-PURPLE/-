// MaterialApp.router + GoRouter. 경로: / · /map · /region/:code · /place/:id
// ?demo=1 → 급수 3 저장 후 /map (회귀 #9)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/assets.dart';
import 'i18n/strings_en.dart';
import 'screens/landing_screen.dart';
import 'screens/map_screen.dart';
import 'screens/placeholder_screen.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';

/// 자산 · 앱 상태를 위젯 트리에 공급
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.assets, required this.appState, required super.child});
  final MalgilAssets assets;
  final AppState appState;

  static AppScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope not found');
    return s!;
  }

  @override
  bool updateShouldNotify(AppScope old) => assets != old.assets || appState != old.appState;
}

class MalgilApp extends StatefulWidget {
  const MalgilApp({super.key, required this.assets, required this.appState});
  final MalgilAssets assets;
  final AppState appState;

  @override
  State<MalgilApp> createState() => _MalgilAppState();
}

class _MalgilAppState extends State<MalgilApp> {
  late final GoRouter _router = buildRouter(widget.appState);

  @override
  Widget build(BuildContext context) {
    return AppScope(
      assets: widget.assets,
      appState: widget.appState,
      child: MaterialApp.router(
        title: '${S.appTitleKo} ${S.appTitleEn}',
        theme: malgilTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

const int demoLevel = 3;

/// demo=1 처리는 라우터 redirect 에서: 어느 경로로 들어와도 급수 3 저장 후 /map
String? demoRedirect(AppState appState, Uri uri) {
  if (uri.queryParameters['demo'] == '1') {
    appState.setLevel(demoLevel);
    return '/map';
  }
  return null;
}

GoRouter buildRouter(AppState appState) => GoRouter(
      initialLocation: '/',
      redirect: (context, state) => demoRedirect(appState, state.uri),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
        GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
        GoRoute(
          path: '/region/:code',
          builder: (context, state) => PlaceholderScreen(title: S.regionTitle, subtitle: state.pathParameters['code']),
        ),
        GoRoute(
          path: '/place/:id',
          builder: (context, state) => PlaceholderScreen(title: S.placeTitle, subtitle: state.pathParameters['id']),
        ),
      ],
    );
