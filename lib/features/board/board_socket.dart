import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/api_client.dart';
import '../../core/api/ws_connect.dart';
import '../../core/config.dart';
import 'board_providers.dart';

/// Realtime board sync (web `useProjectBoard`). Connects to
/// `ws/projects/<id>/board/?token=<access JWT>` (see backend
/// `apps/tasks/routing.py` + `ws_middleware.py`) and applies
/// `task.created|updated|moved|deleted` events to the board.
///
/// Fails silently: any error just leaves the board in request/response mode.
/// Reconnects with exponential backoff (max 5 attempts) except on 4001/4003
/// (unauthenticated / not a member). State is `true` while connected.
class BoardSocket extends AutoDisposeFamilyNotifier<bool, BoardKey> {
  static const _maxRetries = 5;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retryTimer;
  Timer? _refreshDebounce;
  int _retries = 0;
  bool _disposed = false;

  @override
  bool build(BoardKey arg) {
    _disposed = false;
    ref.onDispose(_close);
    Future.microtask(_connect);
    return false;
  }

  void _setConnected(bool v) {
    if (_disposed) return;
    try {
      if (state != v) state = v;
    } catch (_) {}
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final token = ref.read(tokenStorageProvider).access;
      if (token == null || token.isEmpty) return;
      final base = AppConfig.wsBase.endsWith('/')
          ? AppConfig.wsBase.substring(0, AppConfig.wsBase.length - 1)
          : AppConfig.wsBase;
      final uri = Uri.parse(
          '$base/ws/projects/${arg.projectId}/board/?token=${Uri.encodeQueryComponent(token)}');
      final channel = connectSocket(uri);
      _channel = channel;
      await channel.ready;
      if (_disposed) {
        await channel.sink.close(1000);
        return;
      }
      _retries = 0;
      _setConnected(true);
      _sub = channel.stream.listen(
        _onMessage,
        onError: (Object _) => _onClosed(channel.closeCode),
        onDone: () => _onClosed(channel.closeCode),
        cancelOnError: true,
      );
    } catch (_) {
      _onClosed(null);
    }
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final data =
          jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
      if (data is! Map) return;
      final type = '${data['type'] ?? ''}';
      final task = data['task'] is Map
          ? Map<String, dynamic>.from(data['task'] as Map)
          : null;
      final applied = ref
          .read(boardControllerProvider(arg).notifier)
          .applyRemote(type, task);
      if (!applied) ref.invalidate(boardTasksProvider);
      _scheduleSideRefresh();
    } catch (_) {
      // Malformed payloads are ignored.
    }
  }

  /// Header counts / activity / charts refresh — debounced so bursts of
  /// events cause one re-fetch.
  void _scheduleSideRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 800), () {
      if (_disposed) return;
      try {
        ref.invalidate(projectDetailProvider(arg));
        ref.invalidate(projectActivityProvider(arg));
        ref.invalidate(analyticsProvider(arg));
        ref.invalidate(timelineProvider(arg));
      } catch (_) {}
    });
  }

  void _onClosed(int? code) {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _setConnected(false);
    if (_disposed) return;
    if (code == 4001 || code == 4003) return;
    if (_retries >= _maxRetries) return;
    final delay = Duration(milliseconds: 1000 * (1 << _retries));
    _retries++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _connect);
  }

  void _close() {
    _disposed = true;
    _retryTimer?.cancel();
    _refreshDebounce?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close(1000);
    } catch (_) {}
    _channel = null;
  }
}

/// Watch this from the board screen to keep the socket open; value is
/// whether the live connection is up.
final boardSocketProvider = NotifierProvider.autoDispose
    .family<BoardSocket, bool, BoardKey>(BoardSocket.new);
