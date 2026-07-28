import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/widgets.dart';
import '../shell/org_switcher.dart';

/// Home tab — mirrors the web dashboard (`app/(dashboard)/page.jsx` + Topbar):
/// greeting banner, stats, organization cards and the active org's projects.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    final slug = ref.read(activeOrgProvider).valueOrNull?.slug;
    ref.invalidate(orgsProvider);
    if (slug != null) {
      ref.invalidate(projectsProvider(slug));
      ref.invalidate(membersProvider(slug));
    }
    unawaited(ref.read(authProvider.notifier).refreshUser());
    try {
      await ref.read(orgsProvider.future);
    } catch (_) {
      // Error state is rendered by the list itself.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.user));
    final orgsAsync = ref.watch(orgsProvider);
    final active = ref.watch(activeOrgProvider).valueOrNull;

    final banner =
        _WelcomeBanner(user: user, orgCount: orgsAsync.valueOrNull?.length);

    final (String phase, List<Widget> body) =
        orgsAsync.when<(String, List<Widget>)>(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => (
        'loading',
        [banner, const SizedBox(height: 20), const _LoadingBody()]
      ),
      error: (e, _) => (
        'error',
        [
          banner,
          const SizedBox(height: 12),
          ErrorState(error: e, onRetry: () => ref.invalidate(orgsProvider)),
        ]
      ),
      data: (orgs) {
        if (orgs.isEmpty) {
          return (
            'empty',
            [
              banner,
              const SizedBox(height: 12),
              EmptyState(
                icon: Icons.apartment_rounded,
                title: 'No organizations yet',
                message:
                    'Create one to start managing projects with your team.',
                action: TFButton(
                  label: 'Create organization',
                  icon: Icons.add_rounded,
                  onPressed: () => showCreateOrgSheet(context, ref),
                ),
              ),
            ]
          );
        }
        return (
          'data',
          [
            banner,
            const SizedBox(height: 20),
            if (active != null) ...[
              Eyebrow('Overview · ${active.name}'),
              const SizedBox(height: 10),
              _StatsGrid(orgCount: orgs.length, active: active),
              const SizedBox(height: 28),
            ],
            SectionHeader(
              eyebrow: '${orgs.length} total',
              title: 'Your organizations',
              action: _TextAction(
                  label: '+ New',
                  onTap: () => showCreateOrgSheet(context, ref)),
            ),
            const SizedBox(height: 12),
            for (final org in orgs) ...[
              _OrgCard(
                org: org,
                active: org.slug == active?.slug,
                role: userRoleIn(user, org.slug),
              ),
              const SizedBox(height: 10),
            ],
            _NewOrgTile(onTap: () => showCreateOrgSheet(context, ref)),
            if (active != null) ...[
              const SizedBox(height: 28),
              _RecentProjects(org: active),
            ],
          ]
        );
      },
    );

    return Scaffold(
      backgroundColor: TF.bgBase,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: TF.brand,
          backgroundColor: TF.bgElevated,
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: const _TopBar().animate().fadeIn(duration: 300.ms),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.list(children: [
                  for (var i = 0; i < body.length; i++)
                    body[i]
                        .animate(
                            key: ValueKey('$phase-$i'),
                            delay: (45 * i).clamp(0, 600).ms)
                        .fadeIn(duration: 420.ms, curve: Curves.easeOut)
                        .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: 420.ms,
                            curve: Curves.easeOutCubic),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.user));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        const BrandLogo(size: 30, showWordmark: false),
        const SizedBox(width: 12),
        const Expanded(
            child:
                Align(alignment: Alignment.centerLeft, child: OrgSwitcher())),
        const SizedBox(width: 10),
        TFIconButton(
          icon: Icons.add_rounded,
          tooltip: 'New organization',
          onPressed: () => showCreateOrgSheet(context, ref),
        ),
        const SizedBox(width: 8),
        Pressable(
          onTap: () => context.go('/profile'),
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: TF.brandGradient),
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration:
                  const BoxDecoration(shape: BoxShape.circle, color: TF.bgBase),
              child: TFAvatar(
                  name: user?.displayName ?? '?',
                  imageUrl: user?.avatarUrl,
                  size: 34),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Welcome banner ───────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.user, required this.orgCount});
  final User? user;
  final int? orgCount;

  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC'
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final first = user?.firstName.trim() ?? '';
    final name = first.isNotEmpty ? first : (user?.displayName ?? 'there');
    final date =
        '${_days[now.weekday - 1]} · ${_months[now.month - 1]} ${now.day}, ${now.year}';
    final count = orgCount ?? 0;
    final sub = count > 0
        ? 'Your terminal for project orchestration — operational across $count organization${count == 1 ? '' : 's'}.'
        : 'Your terminal for project orchestration. Create your first organization to get started.';

    return Container(
      decoration: BoxDecoration(
        color: TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusXl),
        border: Border.all(color: TF.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(
          right: -60,
          top: -70,
          child: IgnorePointer(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    TF.brand.withValues(alpha: 0.28),
                    TF.brand.withValues(alpha: 0.0)
                  ],
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1.12, 1.12),
                duration: 4.seconds,
                curve: Curves.easeInOut),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: TF.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: TF.success.withValues(alpha: 0.6), blurRadius: 6)
                  ],
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fade(begin: 0.35, end: 1, duration: 1100.ms),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'STATUS: TERMINAL ACTIVE',
                  overflow: TextOverflow.ellipsis,
                  style: TFText.eyebrow(color: TF.brand),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(date,
                style: TFText.mono(
                    size: 11, color: TF.textMuted, letterSpacing: 1.4)),
            const SizedBox(height: 14),
            Text('$greeting, $name', style: TFText.h1()),
            const SizedBox(height: 8),
            Text(sub, style: TFText.body(color: TF.textMuted)),
          ]),
        ),
      ]),
    );
  }
}

// ── Stats ────────────────────────────────────────────────────────────────────

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid({required this.orgCount, required this.active});
  final int orgCount;
  final Organization active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider(active.slug)).valueOrNull;
    final members = ref.watch(membersProvider(active.slug)).valueOrNull;
    final activeProjects = projects?.where((p) => !p.archived).length;

    return Column(children: [
      Row(children: [
        Expanded(
            child: _CountTile(
                label: 'Organizations',
                value: orgCount,
                icon: Icons.apartment_rounded)),
        const SizedBox(width: 10),
        Expanded(
            child: _CountTile(
                label: 'Projects',
                value: activeProjects,
                icon: Icons.view_kanban_outlined,
                accent: TF.info)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: _CountTile(
                label: 'Members',
                value: members?.length,
                icon: Icons.group_outlined,
                accent: TF.success)),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: 'Plan',
            value: Fmt.title(active.plan.isEmpty ? 'free' : active.plan),
            icon: Icons.workspace_premium_outlined,
            accent: planColor(active.plan),
          ),
        ),
      ]),
    ]);
  }
}

/// StatTile whose number counts up when it appears or changes.
class _CountTile extends StatelessWidget {
  const _CountTile(
      {required this.label,
      required this.value,
      required this.icon,
      this.accent = TF.brand});
  final String label;
  final int? value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return StatTile(label: label, value: '—', icon: icon, accent: accent);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value!.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => StatTile(
          label: label,
          value: v.round().toString(),
          icon: icon,
          accent: accent),
    );
  }
}

// ── Organization cards ───────────────────────────────────────────────────────

class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org, required this.active, this.role});
  final Organization org;
  final bool active;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return TFCard(
      highlight: active,
      onTap: () => context.push('/orgs/${org.slug}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: TF.brandLight,
              borderRadius: BorderRadius.circular(TF.radiusMd),
              border: Border.all(color: TF.borderBrand),
            ),
            child:
                const Icon(Icons.apartment_rounded, size: 19, color: TF.brand),
          ),
          const Spacer(),
          if (active) ...[
            const TFBadge('active', color: TF.success, dot: true),
            const SizedBox(width: 6),
          ],
          PlanBadge(org.plan),
        ]),
        const SizedBox(height: 14),
        Text(org.name,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TFText.h3()),
        const SizedBox(height: 2),
        Text('/${org.slug}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TFText.mono(size: 12)),
        const SizedBox(height: 14),
        Container(height: 1, color: TF.borderSubtle),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.group_outlined, size: 15, color: TF.textMuted),
          const SizedBox(width: 6),
          Text('Members', style: TFText.small()),
          if (role != null) ...[
            const SizedBox(width: 8),
            TFBadge.role(role!),
          ],
          const Spacer(),
          const Icon(Icons.arrow_forward_rounded, size: 17, color: TF.brand),
        ]),
      ]),
    );
  }
}

class _NewOrgTile extends StatelessWidget {
  const _NewOrgTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TF.radiusLg),
          border: Border.all(color: TF.borderStrong),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TF.radiusSm),
              border: Border.all(color: TF.borderBrand),
            ),
            child: const Icon(Icons.add_rounded, size: 16, color: TF.brand),
          ),
          const SizedBox(width: 10),
          Text('New organization',
              style: TFText.sans(
                  size: 14, weight: FontWeight.w500, color: TF.textSecondary)),
        ]),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label.toUpperCase(),
          style: TFText.mono(
              size: 11,
              weight: FontWeight.w700,
              color: TF.brand,
              letterSpacing: 1.4),
        ),
      ),
    );
  }
}

// ── Recent projects ──────────────────────────────────────────────────────────

Color _projectStatusColor(String status) => switch (status) {
      'in_progress' => TF.brand,
      'completed' => TF.success,
      'on_hold' => TF.danger,
      'planning' => TF.info,
      _ => TF.textMuted,
    };

class _RecentProjects extends ConsumerWidget {
  const _RecentProjects({required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider(org.slug));

    final header = SectionHeader(
      eyebrow: org.name,
      title: 'Recent projects',
      action:
          _TextAction(label: 'View all', onTap: () => context.go('/projects')),
    );

    final Widget content = projectsAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => Column(key: const ValueKey('loading'), children: [
        for (var i = 0; i < 3; i++) ...[
          const Skeleton(height: 92, radius: TF.radiusLg),
          const SizedBox(height: 10),
        ],
      ]),
      error: (e, _) => TFCard(
        key: const ValueKey('error'),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: TF.danger),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Could not load projects.', style: TFText.body())),
          TFButton(
            label: 'Retry',
            size: TFButtonSize.sm,
            variant: TFButtonVariant.secondary,
            onPressed: () => ref.invalidate(projectsProvider(org.slug)),
          ),
        ]),
      ),
      data: (projects) {
        final list = projects.where((p) => !p.archived).toList()
          ..sort((a, b) {
            final ta = a.updatedAt ?? a.createdAt;
            final tb = b.updatedAt ?? b.createdAt;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        if (list.isEmpty) {
          return TFCard(
            key: const ValueKey('empty'),
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Icon(Icons.view_kanban_outlined,
                  size: 26, color: TF.textMuted),
              const SizedBox(height: 10),
              Text('No projects yet',
                  style: TFText.sans(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Spin up a board for ${org.name} to start tracking work.',
                textAlign: TextAlign.center,
                style: TFText.small(),
              ),
              const SizedBox(height: 14),
              TFButton(
                label: 'Go to projects',
                size: TFButtonSize.sm,
                icon: Icons.arrow_forward_rounded,
                onPressed: () => context.go('/projects'),
              ),
            ]),
          );
        }
        final recent = list.take(5).toList();
        return Column(key: const ValueKey('data'), children: [
          for (var i = 0; i < recent.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProjectRow(slug: org.slug, project: recent[i])
                  .animate(delay: (60 * i).ms)
                  .fadeIn(duration: 350.ms)
                  .slideX(
                      begin: 0.04,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic),
            ),
        ]);
      },
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: 12),
      AnimatedSwitcher(duration: TF.durSlow, child: content),
    ]);
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.slug, required this.project});
  final String slug;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final pct = (p.progressPercent ?? p.progressOverride ?? 0).clamp(0, 100);
    final statusColor = _projectStatusColor(p.status);
    final now = DateTime.now();
    final overdue = p.dueDate != null &&
        p.status != 'completed' &&
        DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day)
            .isBefore(DateTime(now.year, now.month, now.day));

    return TFCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/orgs/$slug/projects/${p.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: TF.priorityColor(p.priority), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TFText.sans(size: 15, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          TFBadge(p.status, color: statusColor),
        ]),
        const SizedBox(height: 12),
        TFProgressBar(value: pct / 100),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.check_box_outlined, size: 13, color: TF.textMuted),
          const SizedBox(width: 4),
          Text('${p.taskCount} task${p.taskCount == 1 ? '' : 's'}',
              style: TFText.mono(size: 11)),
          if (p.dueDate != null) ...[
            const SizedBox(width: 12),
            Icon(Icons.calendar_today_rounded,
                size: 12, color: overdue ? TF.danger : TF.textMuted),
            const SizedBox(width: 4),
            Text(Fmt.short(p.dueDate),
                style: TFText.mono(
                    size: 11, color: overdue ? TF.danger : TF.textMuted)),
          ],
          const Spacer(),
          Text('$pct%',
              style: TFText.mono(
                  size: 11, weight: FontWeight.w700, color: TF.textSecondary)),
        ]),
      ]),
    );
  }
}

// ── Loading skeleton ─────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Skeleton(width: 160, height: 12),
      const SizedBox(height: 12),
      const Row(children: [
        Expanded(child: Skeleton(height: 84, radius: TF.radiusLg)),
        SizedBox(width: 10),
        Expanded(child: Skeleton(height: 84, radius: TF.radiusLg)),
      ]),
      const SizedBox(height: 10),
      const Row(children: [
        Expanded(child: Skeleton(height: 84, radius: TF.radiusLg)),
        SizedBox(width: 10),
        Expanded(child: Skeleton(height: 84, radius: TF.radiusLg)),
      ]),
      const SizedBox(height: 28),
      const Skeleton(width: 200, height: 18),
      const SizedBox(height: 14),
      for (var i = 0; i < 2; i++) ...[
        const Skeleton(height: 140, radius: TF.radiusLg),
        const SizedBox(height: 10),
      ],
    ]);
  }
}
