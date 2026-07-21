import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_error.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import 'buttons.dart';

/// Shimmering placeholder block (web `Skeleton`).
class Skeleton extends StatelessWidget {
  const Skeleton(
      {super.key, this.width, this.height = 14, this.radius = TF.radiusMd});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
          color: TF.bgElevated, borderRadius: BorderRadius.circular(radius)),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1400.ms, color: const Color(0x14FFFFFF));
  }
}

/// A list of skeleton cards for loading states.
class SkeletonList extends StatelessWidget {
  const SkeletonList(
      {super.key,
      this.count = 5,
      this.itemHeight = 76,
      this.padding = const EdgeInsets.all(16)});
  final int count;
  final double itemHeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => Skeleton(height: itemHeight, radius: TF.radiusLg),
    );
  }
}

/// Empty state: icon in a glowing square + title + message + optional action.
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.message,
      this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: TF.brandLight,
              borderRadius: BorderRadius.circular(TF.radiusXl),
              border: Border.all(color: TF.borderBrand),
              boxShadow: TF.shadowGlow,
            ),
            child: Icon(icon, color: TF.brand, size: 26),
          ).animate().scale(
              duration: 450.ms,
              curve: TF.easeBounce,
              begin: const Offset(0.7, 0.7)),
          const SizedBox(height: 18),
          Text(title, style: TFText.h3(), textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!,
                style: TFText.body(color: TF.textMuted),
                textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
      ),
    );
  }
}

/// Error state with retry (web `ErrorState`).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Something went wrong',
      message: errorMessage(error),
      action: onRetry == null
          ? null
          : TFButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              variant: TFButtonVariant.secondary,
              onPressed: onRetry),
    );
  }
}

/// Renders an [AsyncValue] with skeleton/error/data states and a crossfade.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(
      {super.key,
      required this.value,
      required this.data,
      this.loading,
      this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget child = value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (d) => KeyedSubtree(key: const ValueKey('data'), child: data(d)),
      loading: () => KeyedSubtree(
          key: const ValueKey('loading'),
          child: loading ?? const SkeletonList()),
      error: (e, _) => KeyedSubtree(
          key: const ValueKey('error'),
          child: ErrorState(error: e, onRetry: onRetry)),
    );
    return AnimatedSwitcher(
        duration: TF.durSlow, switchInCurve: TF.ease, child: child);
  }
}

enum ToastKind { success, error, info }

/// Floating toast (web `Toaster`).
void showToast(BuildContext context, String message,
    {ToastKind kind = ToastKind.success}) {
  final (icon, color) = switch (kind) {
    ToastKind.success => (Icons.check_circle_rounded, TF.success),
    ToastKind.error => (Icons.error_rounded, TF.danger),
    ToastKind.info => (Icons.info_rounded, TF.info),
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TFText.sans(size: 14))),
      ]),
    ));
}

void showErrorToast(BuildContext context, Object error) =>
    showToast(context, errorMessage(error), kind: ToastKind.error);

/// Themed confirm dialog. Returns true if confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: TF.dur,
    pageBuilder: (ctx, _, __) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TFButton(
            label: 'Cancel',
            variant: TFButtonVariant.ghost,
            size: TFButtonSize.sm,
            onPressed: () => Navigator.pop(ctx, false)),
        TFButton(
          label: confirmLabel,
          size: TFButtonSize.sm,
          variant:
              destructive ? TFButtonVariant.danger : TFButtonVariant.primary,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0)
              .animate(CurvedAnimation(parent: a, curve: TF.ease)),
          child: child),
    ),
  );
  return ok ?? false;
}

/// Themed modal bottom sheet wrapper (the mobile analogue of web `Modal`).
Future<T?> showTFSheet<T>(BuildContext context,
    {required WidgetBuilder builder, bool scrollable = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollable,
    useSafeArea: true,
    backgroundColor: TF.bgSurface,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: builder(ctx),
    ),
  );
}
