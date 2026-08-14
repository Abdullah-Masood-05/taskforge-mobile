import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskforge_mobile/core/auth/auth_controller.dart';
import 'package:taskforge_mobile/core/theme/app_theme.dart';
import 'package:taskforge_mobile/features/auth/login_screen.dart';

/// Holds sign-in open until the test completes it, like a slow server.
final _gate = Completer<void>();

class _PendingAuth extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedOut);

  @override
  Future<void> login(String email, String password) => _gate.future;
}

void main() {
  setUpAll(() async {
    // Use the bundled fonts, as the app does. Without them the test falls
    // back to a much wider font and reports layout overflows that never
    // happen on a device.
    for (final entry in {
      'Geist': 'assets/fonts/Geist-Variable.ttf',
      'JetBrainsMono': 'assets/fonts/JetBrainsMono-Variable.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value));
      await loader.load();
    }
  });

  testWidgets('password toggle still responds while sign-in is pending',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
        GoRoute(path: '/register', builder: (c, s) => const SizedBox()),
        GoRoute(path: '/welcome', builder: (c, s) => const SizedBox()),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith(_PendingAuth.new)],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ));
    await tester.pump();

    await tester.enterText(
        find.byType(TextFormField).at(0), 'admin@taskforge.dev');
    await tester.enterText(find.byType(TextFormField).at(1), 'TaskForge2024!');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Signing in…'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(
      find.byIcon(Icons.visibility_off_outlined),
      findsOneWidget,
      reason: 'the password toggle did not respond while signing in',
    );

    // Let the pending sign-in finish so its slow-request timer is cleared.
    _gate.complete();
    await tester.pump(const Duration(seconds: 10));
  });
}
