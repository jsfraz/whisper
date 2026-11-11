import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';

/// Minimal in-process backend for the Flutter E2E scenarios. It mirrors the
/// server contract closely enough to exercise the real generated API client,
/// the WebSocket client and the app crypto.
class FakeServer {
  FakeServer._(this._server);

  final HttpServer _server;
  final Map<String, int> _wsTokens = {};
  final Map<int, WebSocket> _sockets = {};
  final Map<String, Uint8List> _media = {};
  final Map<String, int> _mediaReceivers = {};
  int _nextUserId = 1;
  int _nextMediaId = 1;

  String get url => 'http://127.0.0.1:${_server.port}';
  String get wsUrl => 'ws://127.0.0.1:${_server.port}/ws';

  static Future<FakeServer> start() async {
    final server = FakeServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._handle);
    return server;
  }

  Future<void> stop() async {
    for (final socket in _sockets.values) {
      await socket.close();
    }
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/ws') {
      await _handleWebSocket(request);
      return;
    }
    try {
      if (path == '/api/auth/register') {
        final body = await _readJson(request);
        _json(request.response, {
          'id': _nextUserId++,
          'username': body['username'],
          'publicKey': body['publicKey'],
          'admin': false,
        });
      } else if (path == '/api/auth') {
        _json(request.response, {
          'accessToken': 'access-1',
          'refreshToken': 'refresh-1',
        });
      } else if (path == '/api/auth/refresh') {
        _json(request.response, {'accessToken': 'access-1'});
      } else if (path == '/api/wsauth') {
        final userId = _userId(request);
        final token = 'ws-$userId-${_wsTokens.length}';
        _wsTokens[token] = userId;
        _json(request.response, {'accessToken': token});
      } else if (path == '/api/media' && request.method == 'POST') {
        await _handleUpload(request);
      } else if (path.startsWith('/api/media/')) {
        final id = path.substring('/api/media/'.length);
        if (request.method == 'GET') {
          _handleDownload(request, id);
        } else if (request.method == 'DELETE') {
          _media.remove(id);
          _mediaReceivers.remove(id);
          request.response.statusCode = HttpStatus.noContent;
        } else {
          request.response.statusCode = HttpStatus.methodNotAllowed;
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('$e');
    } finally {
      await request.response.close();
    }
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final boundary = request.headers.contentType?.parameters['boundary'];
    if (boundary == null) {
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }
    Uint8List? file;
    var receiverId = 0;
    await for (final part in MimeMultipartTransformer(boundary).bind(request)) {
      final disposition = part.headers['content-disposition'] ?? '';
      final bytes = await part
          .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
      if (disposition.contains('name="receiverId"')) {
        receiverId = int.parse(utf8.decode(bytes));
      } else if (disposition.contains('name="file"') &&
          disposition.contains('filename=')) {
        file = Uint8List.fromList(bytes);
      }
    }
    if (file == null) {
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }
    final id = 'media-${_nextMediaId++}';
    _media[id] = file;
    _mediaReceivers[id] = receiverId;
    _json(request.response, {'id': id});
  }

  void _handleDownload(HttpRequest request, String id) {
    final file = _media[id];
    if (file == null) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    if (_userId(request) != _mediaReceivers[id]) {
      request.response.statusCode = HttpStatus.forbidden;
      return;
    }
    request.response.headers.contentType = ContentType.binary;
    request.response.add(file);
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    final token = request.uri.queryParameters['wsAccessToken'];
    final userId = _wsTokens.remove(token);
    if (userId == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _sockets[userId] = socket;
    socket.listen((data) {
      final text = data is String ? data : utf8.decode(data as List<int>);
      final message = jsonDecode(text) as Map<String, dynamic>;
      if (message['type'] != 'message') {
        return;
      }
      final payload = message['payload'] as Map<String, dynamic>;
      final receiverId = payload['receiverId'] as int;
      final response = jsonEncode({
        'type': 'messages',
        'payload': [
          {
            'senderId': userId,
            'content': payload['content'],
            'key': payload['key'],
            'nonce': payload['nonce'],
            'mac': payload['mac'],
            'sentAt': payload['sentAt'],
            'recipientOnline': true,
          }
        ],
      });
      final receiver = _sockets[receiverId];
      if (receiver != null) {
        receiver.add(utf8.encode(response));
      }
    }, onDone: () => _sockets.remove(userId));
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  int _userId(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final token = header.replaceFirst('Bearer ', '');
    return int.tryParse(token.replaceFirst('access-', '')) ?? 0;
  }

  void _json(HttpResponse response, Object body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }
}
