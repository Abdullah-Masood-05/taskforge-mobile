import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/widgets.dart';
import 'task_providers.dart';

/// Absolute URL for an attachment (local-storage backends return a
/// MEDIA_URL-relative path like `/media/...`).
String? _resolveUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return url.startsWith('/')
      ? '${AppConfig.apiBase}$url'
      : '${AppConfig.apiBase}/$url';
}

IconData _iconFor(Attachment a) {
  final t = a.contentType.toLowerCase();
  final n = a.fileName.toLowerCase();
  if (t.startsWith('image/')) return Icons.image_outlined;
  if (t.contains('pdf') || n.endsWith('.pdf')) {
    return Icons.picture_as_pdf_outlined;
  }
  if (t.startsWith('video/')) return Icons.movie_outlined;
  if (t.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (t.contains('zip') || t.contains('compressed') || n.endsWith('.zip')) {
    return Icons.folder_zip_outlined;
  }
  if (t.contains('sheet') ||
      t.contains('csv') ||
      n.endsWith('.csv') ||
      n.endsWith('.xlsx')) {
    return Icons.table_chart_outlined;
  }
  if (t.startsWith('text/') || t.contains('document') || t.contains('word')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// Attachment list: open (download URL in the browser/viewer) and delete.
/// Uploading needs a file picker, so it stays on the web app for now.
class AttachmentsList extends ConsumerWidget {
  const AttachmentsList({super.key, required this.taskRef});
  final TaskRef taskRef;

  Future<void> _open(BuildContext context, Attachment a) async {
    final url = _resolveUrl(a.downloadUrl);
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) {
      showToast(context, 'This file has no download link yet.',
          kind: ToastKind.info);
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        showToast(context, 'Could not open ${a.fileName}.',
            kind: ToastKind.error);
      }
    } catch (_) {
      if (context.mounted) {
        showToast(context, 'Could not open ${a.fileName}.',
            kind: ToastKind.error);
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Attachment a) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete attachment?',
      message: '"${a.fileName}" will be permanently removed from this task.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(taskAttachmentsProvider(taskRef).notifier).delete(a);
      if (context.mounted) showToast(context, 'Attachment deleted');
    } catch (e) {
      if (context.mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments = ref.watch(taskAttachmentsProvider(taskRef));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _WebUploadNote(),
      const SizedBox(height: 14),
      attachments.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => Column(children: [
          for (var i = 0; i < 2; i++)
            const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Skeleton(height: 58, radius: TF.radiusLg)),
        ]),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(children: [
            Text('Could not load attachments.',
                style: TFText.small(color: TF.danger)),
            const SizedBox(height: 10),
            TFButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              size: TFButtonSize.sm,
              variant: TFButtonVariant.secondary,
              onPressed: () => ref.invalidate(taskAttachmentsProvider(taskRef)),
            ),
          ]),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                const Icon(Icons.attach_file_rounded,
                    color: TF.textDisabled, size: 28),
                const SizedBox(height: 8),
                Text('No files attached to this task.', style: TFText.small()),
              ]),
            );
          }
          return Column(children: [
            for (var i = 0; i < items.length; i++)
              _AttachmentTile(
                attachment: items[i],
                onOpen: () => _open(context, items[i]),
                onDelete: () => _delete(context, ref, items[i]),
              )
                  .animate(
                      key: ValueKey(items[i].id),
                      delay: (40 * (i > 8 ? 8 : i)).ms)
                  .fadeIn(duration: 260.ms)
                  .slideY(begin: 0.1, end: 0, curve: TF.ease),
          ]);
        },
      ),
    ]);
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile(
      {required this.attachment, required this.onOpen, required this.onDelete});
  final Attachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final meta = [
      if (a.fileSize > 0) Fmt.fileSize(a.fileSize),
      if (a.uploadedByName != null) a.uploadedByName!,
      if (a.createdAt != null) Fmt.relative(a.createdAt),
    ].join(' · ');
    return TFCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      onTap: onOpen,
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: TF.brandLight,
            borderRadius: BorderRadius.circular(TF.radiusMd),
            border: Border.all(color: TF.borderBrand.withValues(alpha: 0.3)),
          ),
          child: Icon(_iconFor(a), size: 19, color: TF.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              a.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TFText.sans(
                  size: 14, weight: FontWeight.w500, color: TF.textPrimary),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TFText.mono(size: 10.5)),
            ],
          ]),
        ),
        IconButton(
          tooltip: 'Open',
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new_rounded,
              size: 18, color: TF.textSecondary),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded,
              size: 18, color: TF.textMuted),
        ),
      ]),
    );
  }
}

class _WebUploadNote extends StatelessWidget {
  const _WebUploadNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TF.infoLight,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(color: TF.info.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.cloud_upload_outlined, size: 18, color: TF.info),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Uploading files is available on the TaskForge web app. You can open and remove attachments here.',
            style: TFText.small(color: TF.textSecondary),
          ),
        ),
      ]),
    );
  }
}
