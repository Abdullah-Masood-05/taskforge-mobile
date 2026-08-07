import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';
import 'task_providers.dart';

/// Comment thread (oldest first, like the web). Own comments can be deleted.
class CommentsList extends ConsumerWidget {
  const CommentsList({super.key, required this.taskRef});
  final TaskRef taskRef;

  Future<void> _delete(BuildContext context, WidgetRef ref, Comment c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete comment?',
      message: 'This comment will be permanently removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(taskCommentsProvider(taskRef).notifier).delete(c);
    } catch (e) {
      if (context.mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(taskCommentsProvider(taskRef));
    return comments.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => Column(children: [
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(width: 30, height: 30, radius: 15),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(height: 10, width: 120),
                      SizedBox(height: 8),
                      Skeleton(height: 34),
                    ]),
              ),
            ]),
          ),
      ]),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          Text('Could not load comments.',
              style: TFText.small(color: TF.danger)),
          const SizedBox(height: 10),
          TFButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            size: TFButtonSize.sm,
            variant: TFButtonVariant.secondary,
            onPressed: () => ref.invalidate(taskCommentsProvider(taskRef)),
          ),
        ]),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(children: [
              const Icon(Icons.forum_outlined,
                  color: TF.textDisabled, size: 28),
              const SizedBox(height: 10),
              Text('No comments yet. Start the conversation below.',
                  style: TFText.small(), textAlign: TextAlign.center),
            ]),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in items)
              _CommentTile(
                comment: c,
                onDelete: c.isOwn && !isPendingId(c.id)
                    ? () => _delete(context, ref, c)
                    : null,
              )
                  .animate(key: ValueKey(c.id))
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.15, end: 0, curve: TF.ease),
          ],
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.onDelete});
  final Comment comment;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final pending = isPendingId(comment.id);
    final name = comment.author?.displayName ?? 'Unknown';
    return AnimatedOpacity(
      duration: TF.dur,
      opacity: pending ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TFAvatar(name: name, imageUrl: comment.author?.avatarUrl, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
              decoration: BoxDecoration(
                color: comment.isOwn
                    ? TF.brand.withValues(alpha: 0.05)
                    : TF.bgSurface,
                borderRadius: BorderRadius.circular(TF.radiusLg),
                border: Border.all(
                    color: comment.isOwn
                        ? TF.borderBrand.withValues(alpha: 0.25)
                        : TF.borderDefault),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TFText.sans(
                              size: 13,
                              weight: FontWeight.w600,
                              color: TF.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                          pending
                              ? 'sending…'
                              : Fmt.relative(comment.createdAt),
                          style: TFText.mono(size: 10.5)),
                      const Spacer(),
                      if (onDelete != null)
                        SizedBox(
                          width: 28,
                          height: 22,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: 'Delete comment',
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: TF.textMuted),
                          ),
                        )
                      else
                        const SizedBox(height: 22),
                    ]),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SelectableText(comment.body,
                          style: TFText.body(color: TF.textSecondary)),
                    ),
                  ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Composer pinned under the scroll view while the Comments tab is active.
class CommentComposer extends ConsumerStatefulWidget {
  const CommentComposer({super.key, required this.taskRef, this.onSent});
  final TaskRef taskRef;

  /// Called after a comment is queued (e.g. to scroll to the bottom).
  final VoidCallback? onSent;

  @override
  ConsumerState<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<CommentComposer> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    _controller.clear();
    widget.onSent?.call();
    try {
      await ref.read(taskCommentsProvider(widget.taskRef).notifier).add(body);
    } catch (e) {
      if (!mounted) return;
      // Give the text back so nothing is lost.
      if (_controller.text.isEmpty) _controller.text = body;
      showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12,
          10 + (MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : bottomSafe)),
      decoration: const BoxDecoration(
        color: TF.bgSurface,
        border: Border(top: BorderSide(color: TF.borderDefault)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            style: TFText.sans(size: 14.5),
            decoration: const InputDecoration(hintText: 'Write a comment…'),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedScale(
          scale: _hasText ? 1 : 0.9,
          duration: TF.dur,
          curve: TF.easeBounce,
          child: AnimatedOpacity(
            duration: TF.dur,
            opacity: _hasText ? 1 : 0.45,
            child: Pressable(
              onTap: _hasText ? _send : null,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: TF.brandGradient,
                  borderRadius: BorderRadius.circular(TF.radiusMd),
                  boxShadow: _hasText ? TF.shadowGlow : null,
                ),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: TF.onBrand, size: 20),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
