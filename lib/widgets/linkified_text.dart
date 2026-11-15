import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/link_utils.dart';

/// Message text where http(s) addresses are underlined and open in the
/// browser when tapped.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  // Kept per address so a rebuild does not leak recognizers.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizer(String url) {
    return _recognizers.putIfAbsent(
      url,
      () => TapGestureRecognizer()..onTap = () => openLink(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.style?.color ?? DefaultTextStyle.of(context).style.color;
    return Text.rich(
      TextSpan(
        children: [
          for (final part in splitLinks(widget.text))
            part.url == null
                ? TextSpan(text: part.text)
                : TextSpan(
                    text: part.text,
                    recognizer: _recognizer(part.url!),
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
        ],
      ),
      style: widget.style,
    );
  }
}
