// AppState 저장·복원 — interests 토글 · stayCount · SharedPreferences 목으로 라운드트립(새 인스턴스 restore = 새로고침 유지) · 깨진 키 격리
import 'package:flutter_test/flutter_test.dart';
import 'package:malgil/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interests · stayCount (prefs 없음 = 메모리)', () {
    test('toggleInterest — 등록 · 해제 · 빈 지역은 키 제거 · notify · 읽기 전용 뷰', () {
      final s = AppState();
      var n = 0;
      s.addListener(() => n++);
      expect(s.interests, isEmpty);
      expect(s.hasInterest('27200', 's2'), false);
      s.toggleInterest('27200', 's2');
      expect(s.interests, {'27200': ['s2']});
      expect(s.hasInterest('27200', 's2'), true);
      s.toggleInterest('27200', 's1');
      expect(s.interests['27200'], ['s2', 's1']);
      s.toggleInterest('27200', 's2');
      expect(s.interests['27200'], ['s1']);
      s.toggleInterest('27200', 's1');
      expect(s.interests, isEmpty);
      expect(n, 4);
      s.toggleInterest('12730', 's2');
      expect(() => s.interests['12730']!.add('x'), throwsUnsupportedError);
    });

    test('stayCount — 날짜가 있는 지역 수 · 날짜 합', () {
      final s = AppState();
      expect(s.stayCount, (regions: 0, days: 0));
      s.addVisit('27200', '2026-09-13');
      s.addVisit('27200', '2026-09-14');
      s.addVisit('12730', '2026-09-14');
      expect(s.stayCount, (regions: 2, days: 3));
      expect(AppState(visits: {'x': []}).stayCount, (regions: 0, days: 0));
    });

    test('decodeInterests — 형식 어긋난 항목 버림', () {
      expect(AppState.decodeInterests('{"27200":["s2", 3], "x": "bad"}'), {'27200': ['s2']});
      expect(AppState.decodeInterests('[1]'), isEmpty);
      expect(AppState(interests: {'27200': ['s2']}).interests, {'27200': ['s2']});
    });
  });

  group('SharedPreferences 라운드트립', () {
    test('toggleInterest · addVisit · setLevel → 새 인스턴스 restore 에서 복원 (새로고침 유지)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppState(prefs: prefs);
      s.toggleInterest('27200', 's2');
      s.toggleInterest('12730', 's2');
      s.toggleInterest('12730', 's1');
      s.addVisit('27200', '2026-09-14');
      s.setLevel(4);
      await Future<void>.delayed(Duration.zero); // 저장은 fire-and-forget
      expect(prefs.getString(AppState.keyInterests), '{"27200":["s2"],"12730":["s2","s1"]}');
      expect(prefs.getString(AppState.keyVisits), '{"27200":["2026-09-14"]}');

      final r = await AppState.restore();
      expect(identical(r, s), false);
      expect(r.level, 4);
      expect(r.interests, {'27200': ['s2'], '12730': ['s2', 's1']});
      expect(r.visits, {'27200': ['2026-09-14']});
      expect(r.hasInterest('12730', 's1'), true);
      expect(r.stayCount, (regions: 1, days: 1));

      // 복원본에서 해제하면 저장값도 줄어든다
      r.toggleInterest('27200', 's2');
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(AppState.keyInterests), '{"12730":["s2","s1"]}');
    });

    test('키 하나가 깨져도 나머지는 복원 · 저장 계속', () async {
      SharedPreferences.setMockInitialValues({
        AppState.keyInterests: 'not json',
        AppState.keyVisits: '{"27200":["2026-09-14"]}',
        AppState.keyLevel: 3,
      });
      final r = await AppState.restore();
      expect(r.interests, isEmpty);
      expect(r.visits, {'27200': ['2026-09-14']});
      expect(r.level, 3);
      r.toggleInterest('27200', 's2');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppState.keyInterests), '{"27200":["s2"]}');
    });
  });
}
