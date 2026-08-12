import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';

class TaskForgeApp extends ConsumerStatefulWidget {
  const TaskForgeApp({super.key});

  @override
  ConsumerState<TaskForgeApp> createState() => _TaskForgeAppState();
}

class _TaskForgeAppState extends ConsumerState<TaskForgeApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Start waking the (possibly sleeping) API as early as possible.
    ref.read(apiClientProvider).warmUp();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  void _onResume() {
    ref.read(apiClientProvider).warmUp();
    // Reload the org list if it failed while the server was asleep.
    if (ref.exists(orgsProvider) && ref.read(orgsProvider).hasError) {
      ref.invalidate(orgsProvider);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'TaskForge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
