import 'dart:convert';

import 'package:http/http.dart' as http;

/// One KLIPY GIF resolved to the formats this app uses.
class KlipyGif {
  const KlipyGif(
      {required this.title, required this.previewUrl, required this.sendUrl});

  final String title;

  /// Small animated image for the picker grid.
  final String previewUrl;

  /// Medium animated image that is downloaded and sent as a GIF message.
  final String sendUrl;
}

class KlipyException implements Exception {
  KlipyException(this.message);
  final String message;

  @override
  String toString() => 'KlipyException: $message';
}

/// Minimal KLIPY GIF API client (search + trending).
///
/// The app key is a free KLIPY key passed at build time:
/// `flutter run --dart-define=KLIPY_API_KEY=...`.
class KlipyClient {
  static const String apiKey = String.fromEnvironment('KLIPY_API_KEY');
  static const String _host = 'api.klipy.com';
  static const Duration _timeout = Duration(seconds: 10);

  static bool get isConfigured => apiKey.isNotEmpty;

  /// Most popular GIFs, localized by KLIPY.
  static Future<List<KlipyGif>> trending({int page = 1}) async {
    return _fetch(_uri('trending', _query(page)));
  }

  /// GIFs matching [query].
  static Future<List<KlipyGif>> search(String query, {int page = 1}) async {
    return _fetch(_uri('search', {..._query(page), 'q': query}));
  }

  static Uri _uri(String path, Map<String, String> query) {
    return Uri.https(_host, '/api/v1/$apiKey/gifs/$path', query);
  }

  static Map<String, String> _query(int page) {
    return {
      'page': '$page',
      'per_page': '24',
      'content_filter': 'high',
      'format_filter': 'gif,webp',
    };
  }

  static Future<List<KlipyGif>> _fetch(Uri uri) async {
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw KlipyException('KLIPY returned ${response.statusCode}');
    }
    return parse(response.body);
  }

  /// Parses a KLIPY search/trending payload. Public for the unit test.
  static List<KlipyGif> parse(String body) {
    final json = jsonDecode(body);
    if (json is! Map) {
      return [];
    }
    final data = json['data'];
    final items = data is Map ? data['data'] : null;
    if (items is! List) {
      return [];
    }
    final gifs = <KlipyGif>[];
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final file = item['file'];
      if (file is! Map) {
        continue;
      }
      final preview = _url(file, 'sm') ?? _url(file, 'md');
      final send = _url(file, 'md') ?? _url(file, 'sm');
      if (preview == null || send == null) {
        continue;
      }
      gifs.add(KlipyGif(
        title: item['title'] as String? ?? '',
        previewUrl: preview,
        sendUrl: send,
      ));
    }
    return gifs;
  }

  /// Animated WebP first (much smaller than GIF), GIF as the fallback.
  static String? _url(Map file, String size) {
    final bucket = file[size];
    if (bucket is! Map) {
      return null;
    }
    for (final format in const ['webp', 'gif']) {
      final url = bucket[format]?['url'];
      if (url is String && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }
}
