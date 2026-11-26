import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../utils/dialog_utils.dart';
import '../utils/media_utils.dart';
import '../utils/sticker_store.dart';

/// The local sticker collection: tap one to send it, long-press to delete,
/// "+" to import a picture from a file.
class StickerSheet extends StatefulWidget {
  const StickerSheet({super.key});

  /// Shows the collection and returns the sticker the user picked, or null.
  static Future<Sticker?> show(BuildContext context) {
    return showModalBottomSheet<Sticker>(
      context: context,
      showDragHandle: true,
      builder: (_) => const StickerSheet(),
    );
  }

  @override
  State<StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<StickerSheet> {
  List<Sticker> _stickers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stickers = await StickerStore.all();
    if (!mounted) {
      return;
    }
    setState(() {
      _stickers = stickers;
      _loading = false;
    });
  }

  Future<void> _import() async {
    final picked = await MediaUtils.pickMultipleMediaFromGallery();
    var added = 0;
    for (final file in picked) {
      final sticker = await StickerStore.add(
          await file.readAsBytes(), MediaUtils.baseName(file.path));
      if (sticker != null) {
        added++;
      }
    }
    if (picked.isNotEmpty && added == 0) {
      await Fluttertoast.showToast(
          msg: 'stickerUnsupported'.tr(), backgroundColor: Colors.orange);
    }
    await _load();
  }

  Future<void> _delete(Sticker sticker) async {
    await DialogUtils.yesNoDialog(
        context, 'deleteSticker'.tr(), 'deleteStickerConfirm'.tr(), () async {
      await StickerStore.remove(sticker);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 320,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _stickers.length + 1,
                itemBuilder: (context, index) {
                  if (index == _stickers.length) {
                    return InkWell(
                      onTap: _import,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add),
                      ),
                    );
                  }
                  final sticker = _stickers[index];
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, sticker),
                    onLongPress: () => _delete(sticker),
                    child: FutureBuilder<Uint8List>(
                      future: MediaUtils.decryptAtRest(sticker.path),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2));
                        }
                        return Image.memory(snapshot.data!,
                            fit: BoxFit.contain);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
