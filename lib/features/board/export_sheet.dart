import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import 'board_providers.dart';
import 'board_widgets.dart';

/// JSON export (GET /projects/{id}/export/): fetched, previewed and copied to
/// the clipboard — the portable template format the web app downloads.
Future<void> showJsonExportSheet(BuildContext context, BoardKey key) {
  return showTFSheet<void>(context,
      builder: (_) => _JsonExportSheet(boardKey: key));
}

/// PDF report job (web `ExportReport`): POST /reports/, poll every 2s, then
/// open the download URL.
Future<void> showReportExportSheet(BuildContext context, BoardKey key) {
  return showTFSheet<void>(context,
      builder: (_) => _ReportSheet(boardKey: key));
}

class _JsonExportSheet extends ConsumerStatefulWidget {
  const _JsonExportSheet({required this.boardKey});
  final BoardKey boardKey;

  @override
  ConsumerState<_JsonExportSheet> createState() => _JsonExportSheetState();
}

class _JsonExportSheetState extends ConsumerState<_JsonExportSheet> {
  String? _json;
  Object? _error;
  Map<String, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _json = null;
    });
    try {
      final k = widget.boardKey;
      var data =
          await ref.read(repositoryProvider).exportProject(k.slug, k.projectId);
      if (data is String) data = jsonDecode(data);
      final json = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      setState(() {
        _json = json;
        if (data is Map) {
          _counts = {
            'columns': data['statuses'] is List
                ? (data['statuses'] as List).length
                : 0,
            'labels':
                data['labels'] is List ? (data['labels'] as List).length : 0,
            'tasks': data['tasks'] is List ? (data['tasks'] as List).length : 0,
          };
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _copy() async {
    if (_json == null) return;
    await Clipboard.setData(ClipboardData(text: _json!));
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast(context, 'Project JSON copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null) {
      body = Padding(
          padding: const EdgeInsets.all(20),
          child: ErrorState(error: _error!, onRetry: _load));
    } else if (_json == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          Skeleton(height: 18, width: 160),
          SizedBox(height: 12),
          Skeleton(height: 220, radius: TF.radiusLg),
        ]),
      );
    } else {
      body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _counts.entries)
                  TFBadge('${e.value} ${e.key}', color: TF.textSecondary),
                TFBadge('${(_json!.length / 1024).toStringAsFixed(1)} KB',
                    color: TF.brand),
              ]),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: TF.bgBase,
                  borderRadius: BorderRadius.circular(TF.radiusLg),
                  border: Border.all(color: TF.borderDefault),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _json!.length > 6000
                        ? '${_json!.substring(0, 6000)}\n…'
                        : _json!,
                    style: TFText.mono(size: 11, color: TF.textSecondary),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 300.ms),
          ]);
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHeader(title: 'Export JSON', eyebrow: 'Template'),
          Flexible(child: body),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: TFButton(
              label: 'Copy to clipboard',
              icon: Icons.copy_rounded,
              expand: true,
              onPressed: _json == null ? null : _copy,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.boardKey});
  final BoardKey boardKey;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String _status = 'idle'; // idle | pending | processing | completed | failed
  String? _jobId;
  String? _url;
  String? _error;
  Timer? _timer;
  int _polls = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _status = 'pending';
      _error = null;
      _url = null;
      _polls = 0;
    });
    try {
      final job = await ref
          .read(repositoryProvider)
          .createExport(widget.boardKey.projectId);
      _jobId = job['id']?.toString();
      if (!mounted) return;
      if (_jobId == null) throw StateError('No job id');
      _schedulePoll();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'failed';
          _error = errorMessage(e);
        });
      }
    }
  }

  void _schedulePoll() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _poll);
  }

  Future<void> _poll() async {
    final id = _jobId;
    if (id == null || !mounted) return;
    try {
      final job = await ref.read(repositoryProvider).pollExport(id);
      if (!mounted) return;
      final status = '${job['status'] ?? 'pending'}';
      if (status == 'completed') {
        final url = await ref.read(repositoryProvider).exportDownloadUrl(id);
        if (!mounted) return;
        setState(() {
          _status = 'completed';
          _url = url;
        });
      } else if (status == 'failed') {
        setState(() {
          _status = 'failed';
          _error =
              (job['error'] ?? 'Export failed. Please try again.').toString();
        });
      } else {
        _polls++;
        if (_polls > 60) {
          setState(() {
            _status = 'failed';
            _error =
                'The report is taking longer than expected. Try again later.';
          });
          return;
        }
        setState(() => _status = status);
        _schedulePoll();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'failed';
          _error = errorMessage(e);
        });
      }
    }
  }

  Future<void> _open() async {
    final url = _url;
    if (url == null) return;
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showToast(context, 'Could not open the report link',
          kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _status == 'pending' || _status == 'processing';
    final (IconData icon, Color color, String title, String message) =
        switch (_status) {
      'completed' => (
          Icons.check_circle_rounded,
          TF.success,
          'Report ready',
          'Your PDF report has been generated.'
        ),
      'failed' => (
          Icons.error_outline_rounded,
          TF.danger,
          'Export failed',
          _error ?? 'Something went wrong.'
        ),
      'idle' => (
          Icons.picture_as_pdf_outlined,
          TF.brand,
          'PDF project report',
          'Generates a summary of tasks, progress and activity. This runs in the background and takes a few seconds.',
        ),
      _ => (
          Icons.hourglass_top_rounded,
          TF.brand,
          'Generating…',
          'Building your report — hang tight.'
        ),
    };

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Export report', color: TF.brand),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: TF.durSlow,
                child: Column(
                  key: ValueKey(_status),
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(TF.radiusXl),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: running
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: color),
                            )
                          : Icon(icon, color: color, size: 26),
                    ).animate().scale(
                        duration: 400.ms,
                        curve: TF.easeBounce,
                        begin: const Offset(0.8, 0.8)),
                    const SizedBox(height: 14),
                    Text(title, style: TFText.h3()),
                    const SizedBox(height: 6),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: TFText.body(color: TF.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (_status == 'completed')
                TFButton(
                    label: 'Open report',
                    icon: Icons.open_in_new_rounded,
                    expand: true,
                    onPressed: _url == null ? null : _open)
              else
                TFButton(
                  label: _status == 'failed' ? 'Try again' : 'Generate report',
                  icon: Icons.bolt_rounded,
                  expand: true,
                  loading: running,
                  onPressed: running ? null : _start,
                ),
            ]),
      ),
    );
  }
}
