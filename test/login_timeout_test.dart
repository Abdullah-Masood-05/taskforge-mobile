import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskforge_mobile/core/api/api_client.dart';
import 'package:taskforge_mobile/core/api/api_error.dart';
import 'package:taskforge_mobile/core/auth/token_storage.dart';
import 'package:taskforge_mobile/data/repository.dart';

/// Points the app at a server that accepts connections and never answers,
/// like a proxy stalled during a cold start. Needs a real socket, so it only
/// runs when asked:
///
///   flutter test test/login_timeout_test.dart \
///     --dart-define=BLACKHOLE_TEST=true \
///     --dart-define=API_URL=http://127.0.0.1:8765
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const enabled = bool.fromEnvironment('BLACKHOLE_TEST');

  test(
    'sign-in gives up within 45 seconds when the server never answers',
    () async {
      HttpOverrides.global = null;
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 8765);
      final sockets = <Socket>[];
      server.listen(sockets.add);
      addTearDown(() async {
        for (final s in sockets) {
          s.destroy();
        }
        await server.close();
      });

      SharedPreferences.setMockInitialValues({});
      final storage = TokenStorage(await SharedPreferences.getInstance());
      final repo = TaskForgeRepository(ApiClient(storage));

      final sw = Stopwatch()..start();
      Object? error;
      try {
        await repo
            .login('admin@taskforge.dev', 'TaskForge2024!')
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        error = e;
      }
      expect(error, isA<ApiError>(),
          reason: 'sign-in was still waiting after 60 seconds');
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 45)),
        reason: 'sign-in took ${sw.elapsedMilliseconds} ms to give up',
      );
    },
    skip: enabled ? false : 'run with --dart-define=BLACKHOLE_TEST=true',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
