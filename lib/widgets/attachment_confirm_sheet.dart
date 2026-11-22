import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What the sender chose in [AttachmentConfirmSheet]: the caption, whether the
/// attachment travels as a view-once one, and whether it should be edited first.
class AttachmentConfirmResult {
  const AttachmentConfirmResult(
      {required this.caption, this.viewOnce = false, this.edit = false});

  final String caption;
  final bool viewOnce;

  /// The sender wants the editor before sending: crop/draw for a photo, trim
  /// for a video.
  final bool edit;
}

/// Sheet shown after picking an attachment: an optional caption, an optional
/// "view once" switch and a Send/Cancel decision. Owns its
/// [TextEditingController], because the sheet route keeps rebuilding while it
/// animates out.
class AttachmentConfirmSheet extends StatefulWidget {
  /// Number of picked attachments; more than one means an album.
  final int count;
  final String initialCaption;

  /// Whether the picked attachment may be sent as a single view (one visual
  /// attachment, never an album or a file).
  final bool allowViewOnce;

  /// Whether the picker offers the editor (one photo or one video).
  final bool allowEdit;

  const AttachmentConfirmSheet({
    required this.count,
    this.initialCaption = '',
    this.allowViewOnce = false,
    this.allowEdit = false,
    super.key,
  });

  /// Shows the sheet and returns the chosen caption and flags, or null when
  /// cancelled.
  ///
  /// [theme] and [backgroundColor] come from the caller: a modal route renders
  /// above the chat's own Theme, so without them the sheet uses the app theme.
  static Future<AttachmentConfirmResult?> show(BuildContext context,
      {required int count,
      String initialCaption = '',
      bool allowViewOnce = false,
      bool allowEdit = false,
      ThemeData? theme,
      Color? backgroundColor}) {
    return showModalBottomSheet<AttachmentConfirmResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: backgroundColor,
      builder: (ctx) {
        final sheet = AttachmentConfirmSheet(
          count: count,
          initialCaption: initialCaption,
          allowViewOnce: allowViewOnce,
          allowEdit: allowEdit,
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
  bool _viewOnce = false;

  void _send({bool edit = false}) {
    Navigator.pop(
        context,
        AttachmentConfirmResult(
          caption: _controller.text.trim(),
          viewOnce: _viewOnce,
          edit: edit,
        ));
  }

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
          // One visual attachment can be turned into a single view right here,
          // instead of being a separate entry in the attach sheet.
          if (widget.allowViewOnce)
            CheckboxListTile(
              value: _viewOnce,
              onChanged: (value) => setState(() => _viewOnce = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.visibility_off),
              title: Text('attachViewOnce'.tr()),
              subtitle: Text('viewOnceHint'.tr()),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('cancel'.tr()),
              ),
              const Spacer(),
              if (widget.allowEdit)
                TextButton.icon(
                  onPressed: () => _send(edit: true),
                  icon: const Icon(Icons.tune),
                  label: Text('editAttachment'.tr()),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _send,
                child: Text('send'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
