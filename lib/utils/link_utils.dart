import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:sprintf/sprintf.dart';
import 'package:url_launcher/url_launcher.dart';

/// Absolute http(s) addresses in a message text.
final RegExp _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// Splits [text] into plain pieces and links, in order.
///
/// `url` is null for plain text. A sentence-final dot, comma, semicolon or
/// colon is not treated as part of the address.
List<({String text, String? url})> splitLinks(String text) {
  final parts = <({String text, String? url})>[];
  var index = 0;
  for (final match in _urlPattern.allMatches(text)) {
    var end = match.end;
    while (end > match.start && '.,;:'.contains(text[end - 1])) {
      end--;
    }
    if (match.start > index) {
      parts.add((text: text.substring(index, match.start), url: null));
    }
    final url = text.substring(match.start, end);
    parts.add((text: url, url: url));
    index = end;
  }
  if (index < text.length) {
    parts.add((text: text.substring(index), url: null));
  }
  return parts;
}

/// Opens [url] in the browser and reports a failure the way the app does.
Future<void> openLink(String url) async {
  if (!await launchUrl(Uri.parse(url))) {
    await Fluttertoast.showToast(
      msg: sprintf('urlError'.tr(), [url]),
      backgroundColor: Colors.red,
    );
  }
}
