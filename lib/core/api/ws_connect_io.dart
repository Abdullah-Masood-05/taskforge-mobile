import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// Native sockets send no `Origin` header, and Channels'
/// AllowedHostsOriginValidator rejects origin-less handshakes in production.
/// Present the API's own origin, whose host is always in ALLOWED_HOSTS.
WebSocketChannel connectSocket(Uri uri) =>
    IOWebSocketChannel.connect(uri, headers: {'Origin': AppConfig.apiBase});
