import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Sheet shown after picking an attachment: an optional caption and a
/// Send/Cancel decision. Owns its [TextEditingController], because the sheet
/// route keeps rebuilding while it animates out.
class AttachmentConfirmSheet extends StatefulWidget {
  /// Number of picked attachments; more than one means an album.
  final int count;
  final String initialCaption;

  const AttachmentConfirmSheet({
    required this.count,
    this.initialCaption = '',
    super.key,
  });

  /// Shows the sheet and returns the caption, or null when cancelled.
  ///
  /// [theme] and [backgroundColor] come from the caller: a modal route renders
  /// above the chat's own Theme, so without them the sheet uses the app theme.
  static Future<String?> show(BuildContext context,
      {required int count,
      String initialCaption = '',
      ThemeData? theme,
      Color? backgroundColor}) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: backgroundColor,
      builder: (ctx) {
        final sheet = AttachmentConfirmSheet(
          count: count,
          initialCaption: initialCaption,
        );
        return theme == null ? sheet : Theme(data: theme, child: sheet);
      },
    );
  }

  @override
  State<AttachmentConfirmSheet> createState() => _AttachmentConfirmSheetState();
}

class _AttachmentConfirmSheetState extends State<AttachmentConfirmSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialCaption);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.count > 1
                ? '${'sendAlbum'.tr()} (${widget.count})'
                : 'sendAttachment'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(hintText: 'addCaption'.tr()),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('cancel'.tr()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _controller.text.trim()),
                child: Text('send'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
