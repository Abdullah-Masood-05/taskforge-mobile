import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../../widgets/widgets.dart';

/// Root scaffold for the four bottom-nav branches (Home / Projects / Inbox /
/// Profile). Mirrors the web Sidebar's primary navigation in a terminal-style
/// bottom bar and keeps the unread notification badge fresh.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 60);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(_pollEvery, (_) {
      if (mounted) ref.invalidate(unreadCountProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(unreadCountProvider);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onTap(int index) {
    widget.shell
        .goBranch(index, initialLocation: index == widget.shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    return Scaffold(
      backgroundColor: TF.bgBase,
      body: widget.shell,
      bottomNavigationBar: _BottomNav(
        index: widget.shell.currentIndex,
        unread: unread,
        onTap: _onTap,
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _items = <_NavItem>[
  _NavItem(
      'Home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _NavItem('Projects', Icons.view_kanban_outlined, Icons.view_kanban_rounded),
  _NavItem(
      'Inbox', Icons.notifications_none_rounded, Icons.notifications_rounded),
  _NavItem('Profile', Icons.person_outline_rounded, Icons.person_rounded),
];

const _inboxIndex = 2;

class _BottomNav extends StatelessWidget {
  const _BottomNav(
      {required this.index, required this.unread, required this.onTap});

  final int index;
  final int unread;
  final ValueChanged<int> onTap;

  static const _barHeight = 62.0;
  static const _pillWidth = 54.0;
  static const _pillHeight = 30.0;
  static const _pillTop = 8.0;
  static const _railWidth = 28.0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: TF.bgSurface,
        border: Border(top: BorderSide(color: TF.borderDefault)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: _barHeight,
        child: LayoutBuilder(builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / _items.length;
          return Stack(children: [
            // Amber rail on the top hairline — slides between tabs.
            AnimatedPositioned(
              duration: TF.durSlow,
              curve: Curves.easeOutCubic,
              top: 0,
              left: index * tabWidth + (tabWidth - _railWidth) / 2,
              width: _railWidth,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: TF.brandGradient,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(2)),
                  boxShadow: [
                    BoxShadow(
                        color: TF.brand.withValues(alpha: 0.7), blurRadius: 10)
                  ],
                ),
              ),
            ),
            // Soft indicator pill behind the active icon.
            AnimatedPositioned(
              duration: TF.durSlow,
              curve: TF.easeBounce,
              top: _pillTop,
              left: index * tabWidth + (tabWidth - _pillWidth) / 2,
              width: _pillWidth,
              height: _pillHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: TF.brandLight,
                  borderRadius: BorderRadius.circular(TF.radiusXl),
                  border: Border.all(color: TF.brand.withValues(alpha: 0.22)),
                ),
              ),
            ),
            Row(children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: _items[i],
                    selected: i == index,
                    badge: i == _inboxIndex ? unread : 0,
                    onTap: () => onTap(i),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(
      {required this.item,
      required this.selected,
      required this.badge,
      required this.onTap});

  final _NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '${item.label}, $badge unread' : item.label,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: selected ? TF.brand : TF.textMuted),
          duration: TF.dur,
          curve: TF.ease,
          builder: (context, color, _) {
            final c = color ?? TF.textMuted;
            return Padding(
              padding: const EdgeInsets.only(top: _BottomNav._pillTop),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _BottomNav._pillHeight,
                    child: Center(
                      child: Stack(clipBehavior: Clip.none, children: [
                        AnimatedSwitcher(
                          duration: TF.dur,
                          switchInCurve: TF.easeBounce,
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            selected ? item.activeIcon : item.icon,
                            key: ValueKey(selected),
                            size: 21,
                            color: c,
                          ),
                        ),
                        if (badge > 0)
                          Positioned(
                            top: -5,
                            right: -11,
                            child: _CountBadge(count: badge),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TFText.mono(
                      size: 9.5,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? TF.textPrimary : TF.textMuted,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 17),
      decoration: BoxDecoration(
        color: TF.brand,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: TF.bgSurface, width: 2),
        boxShadow: [
          BoxShadow(color: TF.brand.withValues(alpha: 0.45), blurRadius: 8)
        ],
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style:
            TFText.mono(size: 9.5, weight: FontWeight.w700, color: TF.onBrand),
      ),
    ).animate(key: ValueKey(count)).scale(
        begin: const Offset(0.4, 0.4),
        end: const Offset(1, 1),
        duration: 420.ms,
        curve: TF.easeBounce);
  }
}
