import 'package:web_socket_channel/web_socket_channel.dart';

/// Browsers set `Origin` themselves; nothing to add.
WebSocketChannel connectSocket(Uri uri) => WebSocketChannel.connect(uri);
