import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/billing/billing_screen.dart';
import '../features/billing/pricing_screen.dart';
import '../features/board/project_board_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/orgs/org_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/task/task_detail_screen.dart';
import 'auth/auth_controller.dart';
import 'theme/tokens.dart';

/// Route map (mirrors the web app's pages):
///   /welcome, /login, /register                      — public
///   /  /projects  /notifications  /profile           — bottom-nav shell
///   /orgs/:slug                                      — org overview + members
///   /orgs/:slug/billing, /orgs/:slug/pricing
///   /orgs/:slug/projects/:projectId                  — project board dashboard
///   /orgs/:slug/projects/:projectId/tasks/:taskId    — task detail
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider.select((s) => s.status), (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  const publicPaths = {'/welcome', '/login', '/register'};

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final isPublic = publicPaths.contains(loc);
      if (auth.status == AuthStatus.unknown) return null;
      if (!auth.isSignedIn && !isPublic) return '/welcome';
      if (auth.isSignedIn && isPublic) return '/';
      return null;
    },
    routes: [
      GoRoute(
          path: '/welcome',
          pageBuilder: (c, s) => fadeThrough(s, const WelcomeScreen())),
      GoRoute(
          path: '/login',
          pageBuilder: (c, s) => slideUp(s, const LoginScreen())),
      GoRoute(
          path: '/register',
          pageBuilder: (c, s) => slideUp(s, const RegisterScreen())),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/',
                pageBuilder: (c, s) => fadeThrough(s, const DashboardScreen())),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/projects',
                pageBuilder: (c, s) => fadeThrough(s, const ProjectsScreen())),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/notifications',
                pageBuilder: (c, s) =>
                    fadeThrough(s, const NotificationsScreen())),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/profile',
                pageBuilder: (c, s) => fadeThrough(s, const ProfileScreen())),
          ]),
        ],
      ),
      GoRoute(
        path: '/orgs/:slug',
        pageBuilder: (c, s) =>
            slideIn(s, OrgScreen(slug: s.pathParameters['slug']!)),
        routes: [
          GoRoute(
            path: 'billing',
            pageBuilder: (c, s) =>
                slideIn(s, BillingScreen(slug: s.pathParameters['slug']!)),
          ),
          GoRoute(
            path: 'pricing',
            pageBuilder: (c, s) =>
                slideIn(s, PricingScreen(slug: s.pathParameters['slug']!)),
          ),
          GoRoute(
            path: 'projects/:projectId',
            pageBuilder: (c, s) => slideIn(
              s,
              ProjectBoardScreen(
                  slug: s.pathParameters['slug']!,
                  projectId: s.pathParameters['projectId']!),
            ),
            routes: [
              GoRoute(
                path: 'tasks/:taskId',
                pageBuilder: (c, s) => slideUp(
                  s,
                  TaskDetailScreen(
                    slug: s.pathParameters['slug']!,
                    projectId: s.pathParameters['projectId']!,
                    taskId: s.pathParameters['taskId']!,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

// ── Page transitions ─────────────────────────────────────────────────────────

CustomTransitionPage<void> fadeThrough(GoRouterState s, Widget child) =>
    CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: TF.durSlow,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: TF.ease);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
              scale: Tween(begin: 0.985, end: 1.0).animate(curved),
              child: child),
        );
      },
    );

CustomTransitionPage<void> slideIn(GoRouterState s, Widget child) =>
    CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: TF.durSlow,
      reverseTransitionDuration: TF.dur,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0.08, 0), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

CustomTransitionPage<void> slideUp(GoRouterState s, Widget child) =>
    CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: TF.durSlow,
      reverseTransitionDuration: TF.dur,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
