import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/widgets.dart';
import 'board_providers.dart';
import 'board_widgets.dart';

/// Opens the board filter sheet (web `BoardToolbar`): search, priority,
/// assignee and label. Applying updates [boardFiltersProvider], which the
/// board controller watches to re-query tasks.
Future<void> showBoardFilters(
    BuildContext context, WidgetRef ref, BoardKey key) async {
  final current = ref.read(boardFiltersProvider(key));
  final result = await showTFSheet<BoardFilters>(
    context,
    builder: (_) => _FilterSheet(boardKey: key, initial: current),
  );
  if (result != null && context.mounted) {
    ref.read(boardFiltersProvider(key).notifier).state = result;
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.boardKey, required this.initial});
  final BoardKey boardKey;
  final BoardFilters initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late final _search = TextEditingController(text: widget.initial.search);
  late BoardFilters _f = widget.initial;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _apply() =>
      Navigator.of(context).pop(_f.copyWith(search: _search.text.trim()));

  @override
  Widget build(BuildContext context) {
    final k = widget.boardKey;
    final members = ref.watch(membersProvider(k.slug));
    final labels = ref.watch(labelsProvider(k));

    final sections = <Widget>[
      TFTextField(
        hint: 'Search title or description…',
        controller: _search,
        prefixIcon: Icons.search_rounded,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _apply(),
      ),
      const SizedBox(height: 20),
      FieldBlock(
        label: 'Priority',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          ToggleChip(
            label: 'Any',
            selected: _f.priority == null,
            onTap: () => setState(() => _f = _f.copyWith(priority: null)),
          ),
          for (final p in kPriorities)
            ToggleChip(
              label: Fmt.title(p),
              selected: _f.priority == p,
              color: TF.priorityColor(p),
              leading: ColorDot(TF.priorityColor(p), size: 7),
              onTap: () => setState(() =>
                  _f = _f.copyWith(priority: _f.priority == p ? null : p)),
            ),
        ]),
      ),
      FieldBlock(
        label: 'Assignee',
        child: members.when(
          skipLoadingOnRefresh: true,
          data: (list) => Wrap(spacing: 8, runSpacing: 8, children: [
            ToggleChip(
              label: 'Anyone',
              selected: _f.assigneeId == null,
              onTap: () => setState(() => _f = _f.copyWith(assigneeId: null)),
            ),
            for (final m in list)
              ToggleChip(
                label: m.displayName,
                selected: _f.assigneeId == m.userId,
                leading:
                    TFAvatar(name: m.displayName, imageUrl: m.avatar, size: 20),
                onTap: () => setState(
                  () => _f = _f.copyWith(
                      assigneeId: _f.assigneeId == m.userId ? null : m.userId),
                ),
              ),
          ]),
          loading: () => const Skeleton(height: 34, width: 200),
          error: (e, _) =>
              Text(errorMessage(e), style: TFText.small(color: TF.danger)),
        ),
      ),
      FieldBlock(
        label: 'Label',
        child: labels.when(
          skipLoadingOnRefresh: true,
          data: (list) => list.isEmpty
              ? Text('This project has no labels yet.', style: TFText.small())
              : Wrap(spacing: 8, runSpacing: 8, children: [
                  ToggleChip(
                    label: 'Any',
                    selected: _f.labelId == null,
                    onTap: () =>
                        setState(() => _f = _f.copyWith(labelId: null)),
                  ),
                  for (final l in list)
                    ToggleChip(
                      label: l.name,
                      selected: _f.labelId == l.id,
                      color: TF.hex(l.color),
                      leading: ColorDot(TF.hex(l.color)),
                      onTap: () => setState(() => _f = _f.copyWith(
                          labelId: _f.labelId == l.id ? null : l.id)),
                    ),
                ]),
          loading: () => const Skeleton(height: 34, width: 200),
          error: (e, _) =>
              Text(errorMessage(e), style: TFText.small(color: TF.danger)),
        ),
      ),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(
            title: 'Filter board',
            eyebrow: 'Toolbar',
            trailing: TextButton(
              onPressed: () => Navigator.of(context).pop(const BoardFilters()),
              child: Text('Reset',
                  style: TFText.sans(size: 13.5, color: TF.textMuted)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                for (final (i, w) in sections.indexed)
                  w
                      .animate()
                      .fadeIn(delay: (i * 40).ms, duration: 260.ms)
                      .slideY(begin: 0.06, end: 0),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: TF.borderSubtle))),
            child: TFButton(
                label: 'Apply filters',
                icon: Icons.filter_list_rounded,
                expand: true,
                onPressed: _apply),
          ),
        ]),
      ),
    );
  }
}

/// Row of removable chips for active filters, shown above the board.
class ActiveFiltersBar extends ConsumerWidget {
  const ActiveFiltersBar({super.key, required this.boardKey});
  final BoardKey boardKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(boardFiltersProvider(boardKey));
    final members = ref.watch(membersProvider(boardKey.slug)).valueOrNull ??
        const <Member>[];
    final labels =
        ref.watch(labelsProvider(boardKey)).valueOrNull ?? const <Label>[];
    void apply(BoardFilters v) =>
        ref.read(boardFiltersProvider(boardKey).notifier).state = v;

    String memberName(String id) {
      for (final m in members) {
        if (m.userId == id) return m.displayName;
      }
      return 'Assignee';
    }

    Label? label(String id) {
      for (final l in labels) {
        if (l.id == id) return l;
      }
      return null;
    }

    final chips = <Widget>[
      if (f.search.trim().isNotEmpty)
        _FilterPill(
            icon: Icons.search_rounded,
            text: '“${f.search.trim()}”',
            onClear: () => apply(f.copyWith(search: ''))),
      if (f.priority != null)
        _FilterPill(
          dotColor: TF.priorityColor(f.priority),
          text: Fmt.title(f.priority!),
          onClear: () => apply(f.copyWith(priority: null)),
        ),
      if (f.assigneeId != null)
        _FilterPill(
          icon: Icons.person_outline_rounded,
          text: memberName(f.assigneeId!),
          onClear: () => apply(f.copyWith(assigneeId: null)),
        ),
      if (f.labelId != null)
        _FilterPill(
          dotColor: TF.hex(label(f.labelId!)?.color),
          text: label(f.labelId!)?.name ?? 'Label',
          onClear: () => apply(f.copyWith(labelId: null)),
        ),
    ];

    return AnimatedSize(
      duration: TF.dur,
      curve: TF.ease,
      alignment: Alignment.topCenter,
      child: chips.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                children: [
                  for (final c in chips)
                    Padding(padding: const EdgeInsets.only(right: 6), child: c),
                  TextButton(
                    onPressed: () => apply(const BoardFilters()),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text('Clear all',
                        style: TFText.sans(size: 12.5, color: TF.brand)),
                  ),
                ],
              ),
            ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill(
      {required this.text, required this.onClear, this.icon, this.dotColor});
  final String text;
  final VoidCallback onClear;
  final IconData? icon;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 9, right: 4),
      decoration: BoxDecoration(
        color: TF.brandLight,
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.borderBrand),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 13, color: TF.brand),
        if (dotColor != null) ColorDot(dotColor!, size: 7),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TFText.sans(size: 12.5, color: TF.textPrimary)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClear,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, size: 14, color: TF.textSecondary),
          ),
        ),
      ]),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .scaleXY(begin: 0.9, end: 1, duration: 200.ms);
  }
}
