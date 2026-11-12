import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/klipy_client.dart';

/// KLIPY GIF picker: trending on open, debounced search on typing.
/// Pops the chosen [KlipyGif], or null when dismissed.
class GifPickerPage extends StatefulWidget {
  const GifPickerPage({super.key});

  @override
  State<GifPickerPage> createState() => _GifPickerPageState();
}

class _GifPickerPageState extends State<GifPickerPage> {
  final TextEditingController _searchController = TextEditingController();
  List<KlipyGif> _gifs = [];
  bool _loading = true;
  bool _failed = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String query = ''}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final gifs = query.isEmpty
          ? await KlipyClient.trending()
          : await KlipyClient.search(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _gifs = gifs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _load(query: value.trim());
    });
  }

  Widget _body() {
    if (!KlipyClient.isConfigured) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('gifNotConfigured'.tr(), textAlign: TextAlign.center),
      ));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(child: Text('gifLoadFailed'.tr()));
    }
    if (_gifs.isEmpty) {
      return Center(child: Text('gifNoResults'.tr()));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: _gifs.length,
      itemBuilder: (context, index) {
        final gif = _gifs[index];
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(gif),
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Image.network(
              gif.previewUrl,
              fit: BoxFit.cover,
              // Short-lived failures just retry on the next fetch.
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.broken_image),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('gifTitle'.tr()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => _load(query: value.trim()),
              decoration: InputDecoration(
                hintText: 'gifSearchHint'.tr(),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ),
      ),
      body: _body(),
      // KLIPY attribution is required by their terms.
      bottomNavigationBar: SafeArea(
        child: InkWell(
          onTap: () => launchUrl(Uri.parse('https://klipy.com')),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'poweredByKlipy'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }
}
