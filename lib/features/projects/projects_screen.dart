import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import '../shell/org_switcher.dart';
import 'project_card.dart';
import 'project_form_sheet.dart';

enum _Scope { active, archived, all }

enum _Sort { newest, oldest, name, due, priority }

extension on _Scope {
  String get label => switch (this) {
        _Scope.active => 'Active',
        _Scope.archived => 'Archived',
        _Scope.all => 'All',
      };
}

extension on _Sort {
  String get label => switch (this) {
        _Sort.newest => 'Newest first',
        _Sort.oldest => 'Oldest first',
        _Sort.name => 'Name A–Z',
        _Sort.due => 'Due date',
        _Sort.priority => 'Priority',
      };

  IconData get icon => switch (this) {
        _Sort.newest => Icons.south_rounded,
        _Sort.oldest => Icons.north_rounded,
        _Sort.name => Icons.sort_by_alpha_rounded,
        _Sort.due => Icons.event_outlined,
        _Sort.priority => Icons.flag_outlined,
      };
}

const _priorityRank = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};

/// Projects list for the active organization (web
/// `/orgs/[slug]/projects/page.jsx`): search, scope + status filters, sort,
/// create/edit/archive/delete.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _Scope _scope = _Scope.active;
  String? _status; // null = all statuses
  _Sort _sort = _Sort.newest;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<Project> _scoped(List<Project> all) => all.where((p) {
        return switch (_scope) {
          _Scope.active => !p.archived,
          _Scope.archived => p.archived,
          _Scope.all => true,
        };
      }).toList();

  List<Project> _visible(List<Project> all) {
    final q = _query.trim().toLowerCase();
    final list = _scoped(all).where((p) {
      if (_status != null && p.status != _status) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
    }).toList();

    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    switch (_sort) {
      case _Sort.newest:
        list.sort(
            (a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
      case _Sort.oldest:
        list.sort(
            (a, b) => (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch));
      case _Sort.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _Sort.due:
        list.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
      case _Sort.priority:
        list.sort((a, b) => (_priorityRank[a.priority] ?? 9)
            .compareTo(_priorityRank[b.priority] ?? 9));
    }
    return list;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _open(String slug, Project p) =>
      context.push('/orgs/$slug/projects/${p.id}');

  Future<void> _create(String slug) =>
      showProjectFormSheet(context, ref, slug: slug);

  Future<void> _edit(String slug, Project p) =>
      showProjectFormSheet(context, ref, slug: slug, existing: p);

  Future<void> _archive(String slug, Project p) async {
    try {
      await ref.read(repositoryProvider).archiveProject(slug, p.id);
      ref.invalidate(projectsProvider(slug));
      if (mounted) {
        showToast(
            context, p.archived ? 'Project restored' : 'Project archived');
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _delete(String slug, Project p) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete project?',
      message:
          '"${p.name}" and all of its tasks will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(repositoryProvider).deleteProject(slug, p.id);
      ref.invalidate(projectsProvider(slug));
      if (mounted) showToast(context, 'Project deleted');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _actionsSheet(String slug, Project p) async {
    HapticFeedback.mediumImpact();
    final action = await showTFSheet<ProjectAction>(
      context,
      builder: (ctx) => _ProjectActionsSheet(project: p),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case ProjectAction.edit:
        await _edit(slug, p);
      case ProjectAction.archive:
        await _archive(slug, p);
      case ProjectAction.delete:
        await _delete(slug, p);
    }
  }

  Future<void> _pickSort() async {
    final picked = await showTFSheet<_Sort>(
      context,
      builder: (ctx) => _SortSheet(current: _sort),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(activeOrgProvider);
    final org = orgAsync.valueOrNull;
    final slug = org?.slug;

    return Scaffold(
      backgroundColor: TF.bgBase,
      floatingActionButton: slug == null
          ? null
          : Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TF.radiusMd),
                  boxShadow: TF.shadowGlow),
              child: TFButton(
                label: 'New project',
                icon: Icons.add_rounded,
                size: TFButtonSize.lg,
                onPressed: () => _create(slug),
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 250.ms).scale(
              begin: const Offset(0.8, 0.8),
              duration: 450.ms,
              delay: 250.ms,
              curve: TF.easeBounce),
      body: SafeArea(
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Top bar: org switcher + sort.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              const Expanded(
                  child: Align(
                      alignment: Alignment.centerLeft, child: OrgSwitcher())),
              const SizedBox(width: 12),
              TFIconButton(
                  icon: Icons.swap_vert_rounded,
                  tooltip: 'Sort',
                  onPressed: slug == null ? null : _pickSort),
            ]),
          ),
          Expanded(
            child: orgAsync.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const SkeletonList(itemHeight: 150),
              error: (e, _) => ErrorState(
                  error: e, onRetry: () => ref.invalidate(orgsProvider)),
              data: (o) => o == null
                  ? const EmptyState(
                      icon: Icons.apartment_rounded,
                      title: 'No organization yet',
                      message:
                          'Create or join an organization to start organising projects.',
                    )
                  : _body(o.slug),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body(String slug) {
    final projectsAsync = ref.watch(projectsProvider(slug));
    final all = projectsAsync.valueOrNull ?? const <Project>[];

    Future<void> refresh() async {
      try {
        final _ = await ref.refresh(projectsProvider(slug).future);
      } catch (_) {
        // Error state is rendered by AsyncView.
      }
    }

    final header =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18),
      const Eyebrow('Workspace / Projects', color: TF.brand),
      const SizedBox(height: 6),
      Text('Projects', style: TFText.h1()),
      const SizedBox(height: 2),
      AnimatedSwitcher(
        duration: TF.dur,
        child: Text(
          projectsAsync.hasValue
              ? '${all.length} project${all.length == 1 ? '' : 's'} in this organization · ${_sort.label}'
              : 'Loading projects…',
          key:
              ValueKey('${all.length}|${_sort.name}|${projectsAsync.hasValue}'),
          style: TFText.small(),
        ),
      ),
      const SizedBox(height: 16),
      _SearchField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        onClear: () {
          _search.clear();
          setState(() => _query = '');
        },
      ),
      const SizedBox(height: 12),
      _ScopeTabs(value: _scope, onChanged: (s) => setState(() => _scope = s)),
      const SizedBox(height: 10),
      _StatusFilterRow(
        selected: _status,
        counts: {
          for (final s in kProjectStatuses)
            s: _scoped(all).where((p) => p.status == s).length,
        },
        total: _scoped(all).length,
        onChanged: (s) => setState(() => _status = s),
      ),
      const SizedBox(height: 14),
    ])
            .animate()
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.03, end: 0, duration: 300.ms, curve: TF.ease);

    return RefreshIndicator(
      color: TF.brand,
      backgroundColor: TF.bgElevated,
      onRefresh: refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(child: header),
          ),
          ...projectsAsync.when<List<Widget>>(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList.separated(
                  itemCount: 4,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, __) =>
                      const Skeleton(height: 150, radius: TF.radiusLg),
                ),
              ),
            ],
            error: (e, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(
                    error: e,
                    onRetry: () => ref.invalidate(projectsProvider(slug))),
              ),
            ],
            data: (projects) {
              final visible = _visible(projects);
              if (visible.isEmpty) {
                return [
                  SliverFillRemaining(
                      hasScrollBody: false,
                      child: _empty(slug, projects.isEmpty))
                ];
              }
              // Re-key on filter/sort changes so the stagger replays.
              final listKey = '${_scope.name}|$_status|${_sort.name}';
              return [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList.separated(
                    key: ValueKey(listKey),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final p = visible[i];
                      final delay = (45 * math.min(i, 8)).ms;
                      return ProjectCard(
                        key: ValueKey('$listKey|${p.id}'),
                        project: p,
                        onTap: () => _open(slug, p),
                        onLongPress: () => _actionsSheet(slug, p),
                        onEdit: () => _edit(slug, p),
                        onArchive: () => _archive(slug, p),
                        onDelete: () => _delete(slug, p),
                      ).animate().fadeIn(duration: 320.ms, delay: delay).slideY(
                          begin: 0.08,
                          end: 0,
                          duration: 380.ms,
                          delay: delay,
                          curve: Curves.easeOutCubic);
                    },
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _empty(String slug, bool noProjectsAtAll) {
    final filtering = _query.trim().isNotEmpty || _status != null;
    if (noProjectsAtAll) {
      return EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No projects yet',
        message:
            'Projects group your tasks into boards. Create the first one for this organization.',
        action: TFButton(
            label: 'Create your first project',
            icon: Icons.add_rounded,
            onPressed: () => _create(slug)),
      );
    }
    if (filtering) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching projects',
        message: 'Try a different search or clear the filters.',
        action: TFButton(
          label: 'Clear filters',
          variant: TFButtonVariant.secondary,
          icon: Icons.filter_alt_off_outlined,
          onPressed: () {
            _search.clear();
            setState(() {
              _query = '';
              _status = null;
            });
          },
        ),
      );
    }
    return EmptyState(
      icon: _scope == _Scope.archived
          ? Icons.inventory_2_outlined
          : Icons.folder_open_rounded,
      title: _scope == _Scope.archived
          ? 'No archived projects'
          : 'No active projects',
      message: _scope == _Scope.archived
          ? 'Archived projects will show up here.'
          : 'All projects in this organization are archived.',
      action: _scope == _Scope.archived
          ? null
          : TFButton(
              label: 'New project',
              icon: Icons.add_rounded,
              onPressed: () => _create(slug)),
    );
  }
}

// ── Search field ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.controller,
      required this.onChanged,
      required this.onClear});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TFText.sans(size: 14.5),
        decoration: InputDecoration(
          hintText: 'Search projects…',
          prefixIcon:
              const Icon(Icons.search_rounded, size: 18, color: TF.textMuted),
          suffixIcon: AnimatedSwitcher(
            duration: TF.durFast,
            child: value.text.isEmpty
                ? const SizedBox.shrink(key: ValueKey('empty'))
                : IconButton(
                    key: const ValueKey('clear'),
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: TF.textMuted),
                    onPressed: onClear,
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Scope segmented control (Active / Archived / All) ────────────────────────

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({required this.value, required this.onChanged});
  final _Scope value;
  final ValueChanged<_Scope> onChanged;

  @override
  Widget build(BuildContext context) {
    const scopes = _Scope.values;
    final index = scopes.indexOf(value);
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(color: TF.borderSubtle),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / scopes.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: TF.durSlow,
            curve: TF.ease,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: TF.bgElevated,
                borderRadius: BorderRadius.circular(TF.radiusMd),
                border: Border.all(color: TF.borderDefault),
              ),
            ),
          ),
          Row(children: [
            for (final s in scopes)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (s == value) return;
                    HapticFeedback.selectionClick();
                    onChanged(s);
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: TF.dur,
                      style: TFText.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: s == value ? TF.textPrimary : TF.textMuted,
                      ),
                      child: Text(s.label),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

// ── Status filter chips ──────────────────────────────────────────────────────

class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow(
      {required this.selected,
      required this.counts,
      required this.total,
      required this.onChanged});
  final String? selected;
  final Map<String, int> counts;
  final int total;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          _FilterChip(
            label: 'All statuses',
            count: total,
            color: TF.brand,
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final s in kProjectStatuses) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: projectStatusLabel(s),
              count: counts[s] ?? 0,
              color: s == 'planning' ? TF.info : projectStatusColor(s),
              selected: selected == s,
              onTap: () => onChanged(selected == s ? null : s),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label,
      required this.count,
      required this.color,
      required this.selected,
      required this.onTap});
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: TF.dur,
        curve: TF.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : TF.bgSurface,
          borderRadius: BorderRadius.circular(TF.radiusMd),
          border: Border.all(
              color:
                  selected ? color.withValues(alpha: 0.55) : TF.borderDefault),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: TF.dur,
            width: selected ? 6 : 0,
            height: 6,
            margin: EdgeInsets.only(right: selected ? 6 : 0),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Text(
            label,
            style: TFText.sans(
              size: 13,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? color : TF.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Text('$count',
              style: TFText.mono(
                  size: 11, color: selected ? color : TF.textMuted)),
        ]),
      ),
    );
  }
}

// ── Sheets ───────────────────────────────────────────────────────────────────

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current});
  final _Sort current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Sort projects'),
              const SizedBox(height: 12),
              for (final (i, s) in _Sort.values.indexed)
                _SheetRow(
                  icon: s.icon,
                  label: s.label,
                  selected: s == current,
                  onTap: () => Navigator.of(context).pop(s),
                )
                    .animate()
                    .fadeIn(duration: 220.ms, delay: (30 * i).ms)
                    .slideX(begin: 0.04, end: 0, delay: (30 * i).ms),
            ]),
      ),
    );
  }
}

class _ProjectActionsSheet extends StatelessWidget {
  const _ProjectActionsSheet({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _SheetRow(
        icon: Icons.edit_outlined,
        label: 'Edit project',
        onTap: () => Navigator.of(context).pop(ProjectAction.edit),
      ),
      _SheetRow(
        icon: project.archived
            ? Icons.unarchive_outlined
            : Icons.archive_outlined,
        label: project.archived ? 'Unarchive' : 'Archive',
        onTap: () => Navigator.of(context).pop(ProjectAction.archive),
      ),
      _SheetRow(
        icon: Icons.delete_outline_rounded,
        label: 'Delete project',
        color: TF.danger,
        onTap: () => Navigator.of(context).pop(ProjectAction.delete),
      ),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Project'),
              const SizedBox(height: 4),
              Text(project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TFText.h3()),
              const SizedBox(height: 14),
              for (var i = 0; i < rows.length; i++)
                rows[i]
                    .animate()
                    .fadeIn(duration: 220.ms, delay: (40 * i).ms)
                    .slideX(begin: 0.04, end: 0, delay: (40 * i).ms),
            ]),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color,
      this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (selected ? TF.brand : TF.textPrimary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? TF.brandLight : TF.bgElevated,
            borderRadius: BorderRadius.circular(TF.radiusMd),
            border:
                Border.all(color: selected ? TF.borderBrand : TF.borderDefault),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: TFText.sans(
                        size: 14.5, weight: FontWeight.w500, color: fg))),
            if (selected)
              const Icon(Icons.check_rounded, size: 18, color: TF.brand),
          ]),
        ),
      ),
    );
  }
}
