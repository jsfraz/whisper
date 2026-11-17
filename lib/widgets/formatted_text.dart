import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../utils/link_utils.dart';
import '../utils/message_format.dart';

/// Message text with inline formatting, tappable links, phone numbers and
/// addresses, and spoilers that stay covered until tapped.
class FormattedText extends StatefulWidget {
  const FormattedText(
    this.text, {
    this.style,
    this.maxLines,
    this.textAlign,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  State<FormattedText> createState() => _FormattedTextState();
}

class _FormattedTextState extends State<FormattedText> {
  final Map<String, TapGestureRecognizer> _recognizers = {};

  /// Indices of the spoiler pieces the user has opened this session.
  final Set<int> _revealed = {};

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizer(String key, VoidCallback onTap) {
    return _recognizers.putIfAbsent(
        key, () => TapGestureRecognizer()..onTap = onTap);
  }

  Color get _color =>
      widget.style?.color ??
      DefaultTextStyle.of(context).style.color ??
      Colors.black;

  TextSpan _span(MessagePiece piece, int index) {
    switch (piece.style) {
      case MessageStyle.bold:
        return TextSpan(
            text: piece.text,
            style: const TextStyle(fontWeight: FontWeight.bold));
      case MessageStyle.italic:
        return TextSpan(
            text: piece.text,
            style: const TextStyle(fontStyle: FontStyle.italic));
      case MessageStyle.strike:
        return TextSpan(
            text: piece.text,
            style: const TextStyle(decoration: TextDecoration.lineThrough));
      case MessageStyle.mono:
        return TextSpan(
          text: piece.text,
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: _color.withValues(alpha: 0.12),
          ),
        );
      case MessageStyle.spoiler:
        if (_revealed.contains(index)) {
          return TextSpan(
              text: piece.text,
              style:
                  TextStyle(backgroundColor: _color.withValues(alpha: 0.15)));
        }
        return TextSpan(
          text: List.filled(piece.text.length, '█').join(),
          recognizer: _recognizer('spoiler:$index', () {
            setState(() => _revealed.add(index));
          }),
        );
      case MessageStyle.code:
      case MessageStyle.plain:
        break;
    }
    switch (piece.kind) {
      case MessageKind.link:
        return TextSpan(
          text: piece.text,
          recognizer:
              _recognizer('link:${piece.text}', () => openLink(piece.text)),
          style: _inlineLink(TextDecorationStyle.solid),
        );
      case MessageKind.email:
        return TextSpan(
          text: piece.text,
          recognizer: _recognizer(
              'mail:${piece.text}', () => openLink('mailto:${piece.text}')),
          style: _inlineLink(TextDecorationStyle.solid),
        );
      case MessageKind.phone:
        // Underlined like a link: it is something the user taps, not just text.
        return TextSpan(
          text: piece.text,
          recognizer: _recognizer(
              'copy:${piece.kind.name}:${piece.text}', () => _copy(piece.text)),
          style: _inlineLink(TextDecorationStyle.solid),
        );
      case MessageKind.address:
        return TextSpan(
          text: piece.text,
          recognizer: _recognizer(
              'copy:${piece.kind.name}:${piece.text}', () => _copy(piece.text)),
          style: _inlineLink(TextDecorationStyle.dotted),
        );
      case MessageKind.text:
        return TextSpan(text: piece.text);
    }
  }

  /// Underline for everything tappable. Links, e-mails and phone numbers read
  /// as a link; an address is dotted because a tap only copies it.
  TextStyle _inlineLink(TextDecorationStyle style) => TextStyle(
        decoration: TextDecoration.underline,
        decorationStyle: style,
        decorationColor: _color,
      );

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    Fluttertoast.showToast(msg: 'copiedText'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final pieces = parseMessage(widget.text);
    if (pieces.isEmpty) {
      return Text('', style: widget.style);
    }
    // Code blocks read as their own block, so they get a container instead of
    // an inline span. Whole-message maxLines cannot clip through a block.
    // shortcut: a folded message with a code block still shows the block in
    // full, upgrade with a real measurement pass when that shows up in practice.
    final hasBlock = pieces.any((piece) => piece.style == MessageStyle.code);
    if (!hasBlock) {
      return Text.rich(
        TextSpan(children: [
          for (var i = 0; i < pieces.length; i++) _span(pieces[i], i),
        ]),
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
        textAlign: widget.textAlign,
      );
    }

    final runs = <Widget>[];
    var inline = <InlineSpan>[];
    void flushInline() {
      if (inline.isEmpty) {
        return;
      }
      runs.add(Text.rich(TextSpan(children: inline), style: widget.style));
      inline = [];
    }

    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      if (piece.style != MessageStyle.code) {
        inline.add(_span(piece, i));
        continue;
      }
      flushInline();
      runs.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            piece.text,
            style: widget.style?.copyWith(
              fontFamily: 'monospace',
              fontSize: (widget.style?.fontSize ?? 14) * 0.9,
            ),
          ),
        ),
      );
    }
    flushInline();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: runs,
    );
  }
}
