import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import '../shell/org_switcher.dart';

/// Pending invitations for an org (`/members/pending-invitations/`).
final _pendingInvitesProvider =
    FutureProvider.autoDispose.family<List<Invitation>, String>(
  (ref, slug) => ref.watch(repositoryProvider).pendingInvitations(slug),
);

const _roles = ['admin', 'member', 'viewer'];

const _roleHelp = {
  'admin': 'Full access — members, billing and settings.',
  'member': 'Can view and edit projects and tasks.',
  'viewer': 'Read-only access.',
};

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(normalizeWebsite(url));
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _stripScheme(String url) => url
    .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
    .replaceFirst(RegExp(r'/$'), '');

Widget _enter(Widget w, int i) => w
    .animate(delay: (50 * i).clamp(0, 500).ms)
    .fadeIn(duration: 380.ms, curve: Curves.easeOut)
    .slideY(begin: 0.06, end: 0, duration: 380.ms, curve: Curves.easeOutCubic);

/// Organization detail — mirrors web `orgs/[slug]/page.jsx` + MemberTable +
/// InviteModal, plus overview, invitations and settings.
class OrgScreen extends ConsumerStatefulWidget {
  const OrgScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<OrgScreen> createState() => _OrgScreenState();
}

class _OrgScreenState extends ConsumerState<OrgScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  String get slug => widget.slug;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(orgDetailProvider(slug));
    ref.invalidate(membersProvider(slug));
    ref.invalidate(_pendingInvitesProvider(slug));
    ref.invalidate(projectsProvider(slug));
    try {
      await Future.wait([
        ref.read(orgDetailProvider(slug).future),
        ref.read(membersProvider(slug).future),
      ]);
    } catch (_) {
      // Rendered by the views.
    }
  }

  Member? _findMe(List<Member>? members, User? user) {
    if (members == null || user == null) return null;
    final email = user.email.toLowerCase();
    for (final m in members) {
      if ((m.userId.isNotEmpty && m.userId == user.id) ||
          m.email.toLowerCase() == email) {
        return m;
      }
    }
    return null;
  }

  Future<void> _openInvite(String orgName) async {
    final msg = await showTFSheet<String>(context,
        builder: (_) => _InviteSheet(slug: slug, orgName: orgName));
    if (msg != null && mounted) {
      showToast(context, msg);
      _tabs.animateTo(1);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgDetailProvider(slug));
    final members = ref.watch(membersProvider(slug)).valueOrNull;
    final user = ref.watch(authProvider.select((s) => s.user));
    final me = _findMe(members, user);
    final role = me?.role ?? userRoleIn(user, slug);
    final isAdmin = role == 'admin';
    final org = orgAsync.valueOrNull;

    return Scaffold(
      backgroundColor: TF.bgBase,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: _back,
        ),
        titleSpacing: 0,
        title: Row(children: [
          Text('ORG', style: TFText.eyebrow(color: TF.brand)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '/$slug',
              overflow: TextOverflow.ellipsis,
              style: TFText.mono(size: 13, color: TF.textSecondary),
            ),
          ),
        ]),
        actions: [
          if (isAdmin && org != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TFIconButton(
                icon: Icons.person_add_alt_1_rounded,
                size: 36,
                tooltip: 'Invite member',
                onPressed: () => _openInvite(org.name),
              ).animate().fadeIn(duration: 250.ms).scale(
                  begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: TF.durSlow,
        child: orgAsync.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const _OrgLoading(key: ValueKey('loading')),
          error: (e, _) {
            final notFound =
                e is ApiError && (e.status == 404 || e.status == 403);
            if (notFound) {
              return EmptyState(
                key: const ValueKey('notfound'),
                icon: Icons.search_off_rounded,
                title: 'Organization not found',
                message:
                    'It may have been deleted, or you no longer have access.',
                action: TFButton(
                    label: 'Back to dashboard',
                    onPressed: () => context.go('/')),
              );
            }
            return ErrorState(
                key: const ValueKey('error'), error: e, onRetry: _refresh);
          },
          data: (org) => Column(
            key: const ValueKey('data'),
            children: [
              _OrgHeader(
                org: org,
                role: role,
                memberCount: members?.length ?? org.memberCount,
              )
                  .animate()
                  .fadeIn(duration: 350.ms)
                  .slideY(begin: -0.04, end: 0, curve: Curves.easeOutCubic),
              TabBar(
                controller: _tabs,
                labelColor: TF.brand,
                unselectedLabelColor: TF.textMuted,
                indicatorColor: TF.brand,
                indicatorWeight: 2,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: TF.borderDefault,
                overlayColor: const WidgetStatePropertyAll(TF.surfaceHover),
                labelStyle: TFText.mono(
                    size: 11.5, weight: FontWeight.w700, letterSpacing: 1.6),
                unselectedLabelStyle: TFText.mono(
                    size: 11.5, weight: FontWeight.w500, letterSpacing: 1.6),
                tabs: const [
                  Tab(text: 'OVERVIEW'),
                  Tab(text: 'MEMBERS'),
                  Tab(text: 'SETTINGS'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(
                      slug: slug,
                      org: org,
                      onRefresh: _refresh,
                      onShowMembers: () => _tabs.animateTo(1),
                    ),
                    _MembersTab(
                      slug: slug,
                      orgName: org.name,
                      isAdmin: isAdmin,
                      me: me,
                      currentUserEmail: user?.email,
                      onRefresh: _refresh,
                      onInvite: () => _openInvite(org.name),
                    ),
                    _SettingsTab(
                      key: ValueKey('settings-${org.id}'),
                      slug: slug,
                      org: org,
                      isAdmin: isAdmin,
                      onRefresh: _refresh,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _OrgHeader extends StatelessWidget {
  const _OrgHeader(
      {required this.org, required this.role, required this.memberCount});
  final Organization org;
  final String? role;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: TF.brandLight,
              borderRadius: BorderRadius.circular(TF.radiusXl),
              border: Border.all(color: TF.borderBrand),
              boxShadow: TF.shadowGlow,
            ),
            child:
                const Icon(Icons.apartment_rounded, size: 26, color: TF.brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(org.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TFText.h2()),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                PlanBadge(org.plan),
                if (role != null) TFBadge.role(role!),
              ]),
            ]),
          ),
        ]),
        if (org.description.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(org.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TFText.body()),
        ],
        const SizedBox(height: 12),
        Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Meta(
                  icon: Icons.group_outlined,
                  label: '$memberCount member${memberCount == 1 ? '' : 's'}'),
              if (org.createdAt != null)
                _Meta(
                    icon: Icons.schedule_rounded,
                    label: 'Since ${Fmt.short(org.createdAt)}'),
              if (org.website.trim().isNotEmpty)
                Pressable(
                  onTap: () => _openUrl(org.website),
                  child: _Meta(
                      icon: Icons.link_rounded,
                      label: _stripScheme(org.website),
                      color: TF.brand),
                ),
            ]),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(
      {required this.icon, required this.label, this.color = TF.textMuted});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 5),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TFText.mono(size: 11.5, color: color)),
      ),
    ]);
  }
}

class _OrgLoading extends StatelessWidget {
  const _OrgLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        Row(children: [
          Skeleton(width: 52, height: 52, radius: TF.radiusXl),
          SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(width: 180, height: 20),
              SizedBox(height: 8),
              Skeleton(width: 90, height: 16),
            ]),
          ),
        ]),
        SizedBox(height: 16),
        Skeleton(height: 14),
        SizedBox(height: 8),
        Skeleton(width: 220, height: 14),
        SizedBox(height: 24),
        Skeleton(height: 36),
        SizedBox(height: 20),
        Skeleton(height: 84, radius: TF.radiusLg),
        SizedBox(height: 10),
        Skeleton(height: 84, radius: TF.radiusLg),
      ],
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

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

class _TabList extends StatelessWidget {
  const _TabList({required this.onRefresh, required this.children});
  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: TF.brand,
      backgroundColor: TF.bgElevated,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: children,
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, Widget)>[
      (
        'Slug',
        Text('/${org.slug}',
            style: TFText.mono(size: 12.5, color: TF.textPrimary))
      ),
      if (org.ownerEmail.isNotEmpty)
        (
          'Owner',
          Text(org.ownerEmail,
              overflow: TextOverflow.ellipsis, style: TFText.sans(size: 13.5))
        ),
      (
        'Plan',
        Align(alignment: Alignment.centerRight, child: PlanBadge(org.plan))
      ),
      if (org.website.trim().isNotEmpty)
        (
          'Website',
          Pressable(
            onTap: () => _openUrl(org.website),
            child: Text(
              _stripScheme(org.website),
              overflow: TextOverflow.ellipsis,
              style: TFText.sans(size: 13.5, color: TF.brand),
            ),
          ),
        ),
      if (org.createdAt != null)
        (
          'Created',
          Text(Fmt.short(org.createdAt), style: TFText.sans(size: 13.5))
        ),
    ];
    return TFCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : const Border(bottom: BorderSide(color: TF.borderSubtle)),
            ),
            child: Row(children: [
              SizedBox(
                  width: 90,
                  child:
                      Text(rows[i].$1.toUpperCase(), style: TFText.eyebrow())),
              Expanded(
                  child: Align(
                      alignment: Alignment.centerRight, child: rows[i].$2)),
            ]),
          ),
      ]),
    );
  }
}

// ── Overview tab ─────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab(
      {required this.slug,
      required this.org,
      required this.onRefresh,
      required this.onShowMembers});
  final String slug;
  final Organization org;
  final Future<void> Function() onRefresh;
  final VoidCallback onShowMembers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider(slug)).valueOrNull;
    final projects = ref.watch(projectsProvider(slug)).valueOrNull;
    final invites = ref.watch(_pendingInvitesProvider(slug)).valueOrNull;

    final children = <Widget>[
      const Eyebrow('At a glance'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _CountTile(
            label: 'Members',
            value: members?.length ?? org.memberCount,
            icon: Icons.group_outlined,
            accent: TF.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountTile(
            label: 'Projects',
            value: projects?.where((p) => !p.archived).length,
            icon: Icons.view_kanban_outlined,
            accent: TF.info,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: _CountTile(
                label: 'Invites',
                value: invites?.length,
                icon: Icons.mail_outline_rounded)),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: 'Plan',
            value: Fmt.title(org.plan.isEmpty ? 'free' : org.plan),
            icon: Icons.workspace_premium_outlined,
            accent: planColor(org.plan),
          ),
        ),
      ]),
      const SizedBox(height: 26),
      const Eyebrow('Quick links'),
      const SizedBox(height: 10),
      _QuickLink(
        icon: Icons.view_kanban_rounded,
        title: 'Projects',
        subtitle: 'Boards, tasks and timelines',
        onTap: () {
          ref.read(currentOrgProvider.notifier).state = slug;
          context.go('/projects');
        },
      ),
      const SizedBox(height: 8),
      _QuickLink(
        icon: Icons.group_rounded,
        title: 'Members',
        subtitle: 'Roles, access and invitations',
        onTap: onShowMembers,
      ),
      const SizedBox(height: 8),
      _QuickLink(
        icon: Icons.credit_card_rounded,
        title: 'Billing',
        subtitle: 'Subscription and payment details',
        onTap: () => context.push('/orgs/$slug/billing'),
      ),
      const SizedBox(height: 8),
      _QuickLink(
        icon: Icons.sell_outlined,
        title: 'Pricing',
        subtitle: 'Compare plans and upgrade',
        onTap: () => context.push('/orgs/$slug/pricing'),
      ),
      const SizedBox(height: 26),
      const Eyebrow('Details'),
      const SizedBox(height: 10),
      _DetailsCard(org: org),
    ];

    return _TabList(
      onRefresh: onRefresh,
      children: [
        for (var i = 0; i < children.length; i++) _enter(children[i], i)
      ],
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TFCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: TF.brandLight,
            borderRadius: BorderRadius.circular(TF.radiusMd),
            border: Border.all(color: TF.brand.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: 19, color: TF.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TFText.sans(size: 15, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: TFText.small()),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, size: 20, color: TF.textMuted),
      ]),
    );
  }
}

// ── Members tab ──────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab({
    required this.slug,
    required this.orgName,
    required this.isAdmin,
    required this.me,
    required this.currentUserEmail,
    required this.onRefresh,
    required this.onInvite,
  });

  final String slug;
  final String orgName;
  final bool isAdmin;
  final Member? me;
  final String? currentUserEmail;
  final Future<void> Function() onRefresh;
  final VoidCallback onInvite;

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  final Set<String> _busy = {};

  bool _isSelf(Member m) {
    if (widget.me != null) return widget.me!.id == m.id;
    final email = widget.currentUserEmail?.toLowerCase();
    return email != null && m.email.toLowerCase() == email;
  }

  Future<void> _changeRole(Member m, String role) async {
    if (role == m.role || _busy.contains(m.id)) return;
    setState(() => _busy.add(m.id));
    try {
      await ref
          .read(repositoryProvider)
          .updateMemberRole(widget.slug, m.id, role);
      final _ = await ref.refresh(membersProvider(widget.slug).future);
      if (mounted) {
        showToast(context, '${m.displayName} is now ${Fmt.title(role)}');
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(m.id));
    }
  }

  Future<void> _remove(Member m) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove member',
      message:
          'Remove ${m.displayName} from ${widget.orgName}? They will lose access to all of its projects.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(m.id));
    try {
      await ref.read(repositoryProvider).removeMember(widget.slug, m.id);
      ref.invalidate(orgDetailProvider(widget.slug));
      final _ = await ref.refresh(membersProvider(widget.slug).future);
      if (mounted) showToast(context, '${m.displayName} removed');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(m.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider(widget.slug));
    final invitesAsync = ref.watch(_pendingInvitesProvider(widget.slug));

    final membersView = membersAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => Column(children: [
        for (var i = 0; i < 4; i++) ...[
          const Skeleton(height: 68, radius: TF.radiusLg),
          const SizedBox(height: 8),
        ],
      ]),
      error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(membersProvider(widget.slug))),
      data: (members) => Column(children: [
        for (var i = 0; i < members.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MemberTile(
              key: ValueKey(members[i].id),
              member: members[i],
              isSelf: _isSelf(members[i]),
              canManage: widget.isAdmin && !_isSelf(members[i]),
              busy: _busy.contains(members[i].id),
              onRole: (r) => _changeRole(members[i], r),
              onRemove: () => _remove(members[i]),
            )
                .animate(delay: (40 * i).clamp(0, 400).ms)
                .fadeIn(duration: 300.ms)
                .slideX(
                    begin: 0.03,
                    end: 0,
                    duration: 300.ms,
                    curve: Curves.easeOutCubic),
          ),
      ]),
    );

    final invitesView = invitesAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const Skeleton(height: 60, radius: TF.radiusLg),
      error: (e, _) => TFCard(
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: TF.danger),
          const SizedBox(width: 10),
          Expanded(
              child: Text(errorMessage(e),
                  style: TFText.small(color: TF.textSecondary))),
          TFButton(
            label: 'Retry',
            size: TFButtonSize.sm,
            variant: TFButtonVariant.secondary,
            onPressed: () =>
                ref.invalidate(_pendingInvitesProvider(widget.slug)),
          ),
        ]),
      ),
      data: (invites) => invites.isEmpty
          ? TFCard(
              child: Row(children: [
                const Icon(Icons.mark_email_read_outlined,
                    size: 18, color: TF.textMuted),
                const SizedBox(width: 10),
                Expanded(
                    child:
                        Text('No pending invitations.', style: TFText.small())),
              ]),
            )
          : Column(children: [
              for (var i = 0; i < invites.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _InvitationTile(invite: invites[i])
                      .animate(delay: (40 * i).clamp(0, 400).ms)
                      .fadeIn(duration: 300.ms),
                ),
            ]),
    );

    final count = membersAsync.valueOrNull?.length;
    final children = <Widget>[
      SectionHeader(
        eyebrow: 'Team',
        title: count == null ? 'Members' : 'Members ($count)',
        action: widget.isAdmin
            ? TFButton(
                label: 'Invite',
                icon: Icons.person_add_alt_1_rounded,
                size: TFButtonSize.sm,
                onPressed: widget.onInvite,
              )
            : null,
      ),
      if (!widget.isAdmin) ...[
        const SizedBox(height: 6),
        Text('Only admins can change roles or invite people.',
            style: TFText.small()),
      ],
      const SizedBox(height: 14),
      membersView,
      const SizedBox(height: 24),
      const SectionHeader(
          eyebrow: 'Awaiting response', title: 'Pending invitations'),
      const SizedBox(height: 12),
      invitesView,
    ];

    return _TabList(onRefresh: widget.onRefresh, children: children);
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    super.key,
    required this.member,
    required this.isSelf,
    required this.canManage,
    required this.busy,
    required this.onRole,
    required this.onRemove,
  });

  final Member member;
  final bool isSelf;
  final bool canManage;
  final bool busy;
  final ValueChanged<String> onRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final Widget trailing;
    if (busy) {
      trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: TF.brand),
      );
    } else if (canManage) {
      trailing = PopupMenuButton<String>(
        tooltip: 'Manage member',
        position: PopupMenuPosition.under,
        onSelected: (v) => v == '__remove__' ? onRemove() : onRole(v),
        itemBuilder: (_) => [
          for (final r in _roles)
            PopupMenuItem<String>(
              value: r,
              child: Row(children: [
                SizedBox(
                  width: 22,
                  child: r == m.role
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: TF.brand)
                      : null,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Fmt.title(r),
                            style: TFText.sans(
                                size: 14,
                                weight: FontWeight.w600,
                                color: TF.roleColor(r))),
                        Text(_roleHelp[r] ?? '', style: TFText.small()),
                      ]),
                ),
              ]),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: '__remove__',
            child: Row(children: [
              const SizedBox(
                  width: 22,
                  child: Icon(Icons.person_remove_outlined,
                      size: 17, color: TF.danger)),
              const SizedBox(width: 6),
              Text('Remove from organization',
                  style: TFText.sans(size: 14, color: TF.danger)),
            ]),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            TFBadge.role(m.role),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded,
                size: 18, color: TF.textMuted),
          ]),
        ),
      );
    } else {
      trailing = TFBadge.role(m.role);
    }

    return TFCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      highlight: isSelf,
      child: Row(children: [
        TFAvatar(name: m.displayName, imageUrl: m.avatar, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(
                  m.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TFText.sans(size: 14.5, weight: FontWeight.w600),
                ),
              ),
              if (isSelf) ...[
                const SizedBox(width: 6),
                const TFBadge('you', color: TF.info),
              ],
            ]),
            const SizedBox(height: 2),
            Text(m.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TFText.small()),
            if (m.joinedAt != null) ...[
              const SizedBox(height: 3),
              Text('JOINED ${Fmt.short(m.joinedAt).toUpperCase()}',
                  style: TFText.mono(
                      size: 10, color: TF.textDisabled, letterSpacing: 1)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
            duration: TF.dur,
            child: KeyedSubtree(
                key: ValueKey('$busy-${m.role}'), child: trailing)),
      ]),
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({required this.invite});
  final Invitation invite;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (invite.createdAt != null) 'Sent ${Fmt.relative(invite.createdAt)}',
      if (invite.expiresAt != null) 'expires ${Fmt.short(invite.expiresAt)}',
    ];
    return TFCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: TF.bgOverlay,
            shape: BoxShape.circle,
            border: Border.all(color: TF.borderDefault),
          ),
          child: const Icon(Icons.mail_outline_rounded,
              size: 18, color: TF.textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(invite.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TFText.sans(size: 14.5, weight: FontWeight.w600)),
            if (parts.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(parts.join(' · '), style: TFText.small()),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          TFBadge(invite.status, color: TF.warning, dot: true),
          const SizedBox(height: 5),
          TFBadge.role(invite.role),
        ]),
      ]),
    );
  }
}

// ── Invite sheet ─────────────────────────────────────────────────────────────

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.slug, required this.orgName});
  final String slug;
  final String orgName;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String _role = 'member';
  bool _sending = false;
  String? _emailError;
  String? _serverError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _emailError = null;
      _serverError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    setState(() => _sending = true);
    try {
      final res = await ref
          .read(repositoryProvider)
          .inviteMember(widget.slug, email: email, role: _role);
      ref.invalidate(membersProvider(widget.slug));
      ref.invalidate(_pendingInvitesProvider(widget.slug));
      ref.invalidate(orgDetailProvider(widget.slug));
      final addedDirectly = res is Map && res['user_email'] != null;
      if (!mounted) return;
      Navigator.of(context).pop(addedDirectly
          ? '$email was added to ${widget.orgName}'
          : 'Invitation sent to $email');
    } on ApiError catch (e) {
      if (!mounted) return;
      final emailErr = e.fieldError('email');
      setState(() {
        _sending = false;
        _emailError = emailErr;
        _serverError =
            emailErr == null ? (e.fieldError('role') ?? e.friendly) : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _serverError = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Eyebrow(widget.orgName, color: TF.brand),
              const SizedBox(height: 4),
              Text('Invite team member', style: TFText.h2()),
              const SizedBox(height: 6),
              Text(
                'Existing TaskForge users are added right away; everyone else gets a pending invitation.',
                style: TFText.body(color: TF.textMuted),
              ),
              const SizedBox(height: 20),
              AnimatedSize(
                duration: TF.dur,
                curve: TF.ease,
                child: _serverError == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: TF.dangerLight,
                            borderRadius: BorderRadius.circular(TF.radiusMd),
                            border: Border.all(
                                color: TF.danger.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 18, color: TF.danger),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(_serverError!,
                                        style: TFText.sans(
                                            size: 13.5, color: TF.danger))),
                              ]),
                        )
                            .animate()
                            .fadeIn(duration: 200.ms)
                            .shakeX(hz: 4, amount: 3, duration: 300.ms),
                      ),
              ),
              TFTextField(
                label: 'Email address',
                hint: 'colleague@company.com',
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.alternate_email_rounded,
                autofillHints: const [AutofillHints.email],
                errorText: _emailError,
                validator: (v) => _emailRe.hasMatch((v ?? '').trim())
                    ? null
                    : 'Enter a valid email address.',
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: 18),
              Text('Role',
                  style: TFText.sans(
                      size: 13,
                      weight: FontWeight.w500,
                      color: TF.textSecondary)),
              const SizedBox(height: 8),
              ChoiceChips<String>(
                options: _roles,
                value: _role,
                onChanged: (r) => setState(() => _role = r),
                labelOf: Fmt.title,
                colorOf: TF.roleColor,
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: TF.dur,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Row(
                  key: ValueKey(_role),
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: TF.roleColor(_role)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(_roleHelp[_role] ?? '',
                            style: TFText.small())),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TFButton(
                    label: 'Cancel',
                    variant: TFButtonVariant.secondary,
                    expand: true,
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TFButton(
                    label: 'Send invite',
                    icon: Icons.send_rounded,
                    expand: true,
                    loading: _sending,
                    onPressed: _send,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Settings tab ─────────────────────────────────────────────────────────────

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab(
      {super.key,
      required this.slug,
      required this.org,
      required this.isAdmin,
      required this.onRefresh});
  final String slug;
  final Organization org;
  final bool isAdmin;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.org.name);
  late final _description = TextEditingController(text: widget.org.description);
  late final _website = TextEditingController(text: widget.org.website);
  bool _saving = false;
  bool _deleting = false;
  Map<String, String?> _fieldErrors = const {};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _website.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != widget.org.name ||
      _description.text.trim() != widget.org.description ||
      normalizeWebsite(_website.text) != widget.org.website;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _fieldErrors = const {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final updated =
          await ref.read(repositoryProvider).updateOrg(widget.slug, {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'website': normalizeWebsite(_website.text),
      });
      _website.text = updated.website;
      ref.invalidate(orgDetailProvider(widget.slug));
      ref.invalidate(orgsProvider);
      if (mounted) showToast(context, 'Organization updated');
    } on ApiError catch (e) {
      if (!mounted) return;
      final fields = {
        'name': e.fieldError('name'),
        'description': e.fieldError('description'),
        'website': e.fieldError('website'),
      };
      setState(() => _fieldErrors = fields);
      if (fields.values.every((v) => v == null)) showErrorToast(context, e);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final org = widget.org;
    final ok = await confirmDialog(
      context,
      title: 'Delete ${org.name}?',
      message:
          'This removes the organization and all of its projects and tasks for every member. This cannot be undone.',
      confirmLabel: 'Delete organization',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(repositoryProvider).deleteOrg(widget.slug);
      if (ref.read(currentOrgProvider) == widget.slug) {
        ref.read(currentOrgProvider.notifier).state = null;
      }
      ref.invalidate(orgsProvider);
      unawaited(ref.read(authProvider.notifier).refreshUser());
      if (!mounted) return;
      showToast(context, '${org.name} deleted');
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!widget.isAdmin) {
      final children = <Widget>[
        TFCard(
          color: TF.infoLight,
          child: Row(children: [
            const Icon(Icons.lock_outline_rounded, size: 18, color: TF.info),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Only organization admins can change settings.',
                style: TFText.sans(size: 13.5, color: TF.textSecondary),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        const Eyebrow('Organization'),
        const SizedBox(height: 10),
        _DetailsCard(org: widget.org),
      ];
      return _TabList(
        onRefresh: widget.onRefresh,
        children: [
          for (var i = 0; i < children.length; i++) _enter(children[i], i)
        ],
      );
    }

    final children = <Widget>[
      const Eyebrow('General'),
      const SizedBox(height: 10),
      TFCard(
        child: Form(
          key: _formKey,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TFTextField(
              label: 'Name',
              controller: _name,
              textInputAction: TextInputAction.next,
              errorText: _fieldErrors['name'],
              onChanged: (_) => setState(() {}),
              validator: (v) => (v ?? '').trim().length < 2
                  ? 'Name must be at least 2 characters.'
                  : null,
            ),
            const SizedBox(height: 14),
            TFTextField(
              label: 'Description',
              hint: 'What does your team do?',
              controller: _description,
              maxLines: 4,
              minLines: 2,
              errorText: _fieldErrors['description'],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            TFTextField(
              label: 'Website',
              hint: 'https://example.com',
              controller: _website,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              errorText: _fieldErrors['website'],
              validator: validateWebsite,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: TFButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _dirty ? _save : null,
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 26),
      const Eyebrow('Workspace'),
      const SizedBox(height: 10),
      _DetailsCard(org: widget.org),
      const SizedBox(height: 26),
      const Eyebrow('Danger zone', color: TF.danger),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TF.danger.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(TF.radiusLg),
          border: Border.all(color: TF.danger.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Delete organization',
              style: TFText.sans(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Permanently remove ${widget.org.name}, its projects, tasks and member access.',
            style: TFText.small(),
          ),
          const SizedBox(height: 14),
          TFButton(
            label: 'Delete organization',
            icon: Icons.delete_outline_rounded,
            variant: TFButtonVariant.danger,
            loading: _deleting,
            onPressed: _delete,
          ),
        ]),
      ),
    ];

    return _TabList(
      onRefresh: widget.onRefresh,
      children: [
        for (var i = 0; i < children.length; i++) _enter(children[i], i)
      ],
    );
  }
}
