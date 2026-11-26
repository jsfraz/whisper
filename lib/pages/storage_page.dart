import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../utils/cache_utils.dart';
import '../utils/media_utils.dart';
import '../utils/storage_utils.dart';
import '../widgets/settings_tile.dart';

/// What attachments cost on this device: per conversation, plus the two ways to
/// get the space back.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  /// Auto-delete choices in days; 0 keeps the media forever.
  static const List<int> _autoDeleteChoices = [0, 7, 30, 90];

  List<ConversationUsage> _usage = const [];
  Map<String, String> _names = {};
  int _days = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final usage = await StorageUtils.usageByConversation();
    final names = <String, String>{};
    for (final entry in usage) {
      final user = await CacheUtils.getUserById(entry.conversationId);
      names[entry.conversationId] = user?.username ?? entry.conversationId;
    }
    final days = await CacheUtils.getAutoDeleteMediaDays();
    if (!mounted) {
      return;
    }
    setState(() {
      _usage = usage;
      _names = names;
      _days = days;
      _loading = false;
    });
  }

  Future<void> _setDays(int days) async {
    setState(() => _days = days);
    await CacheUtils.setAutoDeleteMediaDays(days);
    final freed = days == 0 ? 0 : await StorageUtils.purgeOlderThanDays(days);
    await _load();
    if (freed > 0 && mounted) {
      await Fluttertoast.showToast(
          msg: '${'storagePurged'.tr()} ${MediaUtils.formatBytes(freed)}');
    }
  }

  Future<void> _clearCache() async {
    await StorageUtils.clearCache();
    if (mounted) {
      await Fluttertoast.showToast(msg: 'storageCacheCleared'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes = _usage.fold<int>(0, (sum, entry) => sum + entry.bytes);
    final totalFiles =
        _usage.fold<int>(0, (sum, entry) => sum + entry.attachments);
    return Scaffold(
      appBar: AppBar(title: Text('storageTitle'.tr())),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(MediaUtils.formatBytes(totalBytes),
                            style: Theme.of(context).textTheme.headlineMedium),
                        Text(
                          '${'storageTotal'.tr()} · $totalFiles ${'storageMediaCount'.tr()}',
                        ),
                      ],
                    ),
                  ),
                  const Divider(thickness: 1, indent: 10, endIndent: 10),
                  SettingsTile(
                    icon: Icons.auto_delete,
                    label: 'storageAutoDelete'.tr(),
                    onPressed: () => _setDays(_days),
                    trailing: DropdownButton<int>(
                      value: _days,
                      underline: const SizedBox.shrink(),
                      onChanged: (days) {
                        if (days != null) {
                          _setDays(days);
                        }
                      },
                      items: [
                        for (final days in _autoDeleteChoices)
                          DropdownMenuItem(
                            value: days,
                            child: Text(days == 0
                                ? 'storageNever'.tr()
                                : '$days ${'storageDaysSuffix'.tr()}'),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'storageSingleDelivery'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.cleaning_services,
                    label: 'storageClearCache'.tr(),
                    onPressed: _clearCache,
                  ),
                  const Divider(thickness: 1, indent: 10, endIndent: 10),
                  if (_usage.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('storageEmpty'.tr()),
                    )
                  else
                    for (final usage in _usage)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(_names[usage.conversationId] ?? ''),
                        subtitle: Text(
                          '${usage.attachments} ${'storageMediaCount'.tr()}',
                        ),
                        trailing: Text(MediaUtils.formatBytes(usage.bytes)),
                      ),
                ],
              ),
      ),
    );
  }
}
