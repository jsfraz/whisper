import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum _EditMode { preview, crop, draw }

/// Crop, rotate and draw on a photo before it leaves the device.
///
/// Returns the edited bytes from [open], or null when the user backs out. The
/// strokes and the rotation are composited into a PNG at the original
/// resolution, so nothing is lost to the preview size.
class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage(this.bytes, {super.key});

  final Uint8List bytes;

  /// Opens the editor and returns the edited bytes, or null.
  static Future<Uint8List?> open(BuildContext context, Uint8List bytes) {
    return Navigator.push<Uint8List>(
        context, MaterialPageRoute(builder: (_) => ImageEditorPage(bytes)));
  }

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  static const Color _ink = Color(0xFFFF3B30);

  final CropController _cropController = CropController();
  late Uint8List _bytes = widget.bytes;
  _EditMode _mode = _EditMode.preview;
  final List<List<Offset>> _strokes = [];
  bool _busy = false;

  /// Width of a stroke relative to the picture, so the line looks the same at
  /// any screen size and at the exported resolution.
  static const double _strokeFraction = 1 / 60;

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      final rendered = await _render(_bytes, _strokes, quarterTurns: 1);
      _strokes.clear();
      setState(() => _bytes = rendered);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      final rendered = await _render(_bytes, _strokes);
      if (mounted) {
        Navigator.pop(context, rendered);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _undo() {
    if (_strokes.isEmpty) {
      return;
    }
    setState(() => _strokes.removeLast());
  }

  /// Draws [strokes] over the decoded [base] and rotates by [quarterTurns] 90°
  /// steps, all at the image's own resolution.
  Future<Uint8List> _render(Uint8List base, List<List<Offset>> strokes,
      {int quarterTurns = 0}) async {
    final codec = await ui.instantiateImageCodec(base);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final swap = quarterTurns.isOdd;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (swap) {
      canvas.translate(height.toDouble(), 0);
      canvas.rotate(1.5707963267948966);
    }
    canvas.drawImage(image, Offset.zero, Paint());
    final paint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * _strokeFraction;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        final point = stroke.first;
        canvas.drawPoints(ui.PointMode.points,
            [Offset(point.dx * width, point.dy * height)], paint);
        continue;
      }
      final path = Path();
      for (var i = 0; i < stroke.length; i++) {
        final point = Offset(stroke[i].dx * width, stroke[i].dy * height);
        i == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final output =
        await picture.toImage(swap ? height : width, swap ? width : height);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    output.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('editImage'.tr()),
        actions: [
          IconButton(
            tooltip: 'rotate'.tr(),
            onPressed: _busy || _mode == _EditMode.crop ? null : _rotate,
            icon: const Icon(Icons.rotate_90_degrees_ccw),
          ),
          IconButton(
            tooltip: 'crop'.tr(),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _mode = _mode == _EditMode.crop
                          ? _EditMode.preview
                          : _EditMode.crop;
                    }),
            icon: Icon(_mode == _EditMode.crop ? Icons.check : Icons.crop),
          ),
          IconButton(
            tooltip: 'draw'.tr(),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _mode = _mode == _EditMode.draw
                          ? _EditMode.preview
                          : _EditMode.draw;
                    }),
            icon: const Icon(Icons.edit),
          ),
          if (_mode == _EditMode.draw)
            IconButton(
              tooltip: 'undo'.tr(),
              onPressed: _strokes.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo),
            ),
          IconButton(
            tooltip: 'save'.tr(),
            onPressed: _busy ? null : _done,
            icon: const Icon(Icons.check_circle),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _mode == _EditMode.crop
              ? _cropView()
              : _drawView(),
    );
  }

  Widget _cropView() {
    return Column(
      children: [
        Expanded(
          child: Crop(
            image: _bytes,
            controller: _cropController,
            onCropped: (result) {
              switch (result) {
                case CropSuccess(:final croppedImage):
                  setState(() {
                    _bytes = croppedImage;
                    _strokes.clear();
                    _mode = _EditMode.preview;
                  });
                case CropFailure():
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('mediaError'.tr())));
              }
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _cropController.crop(),
                child: Text('applyCrop'.tr()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _drawView() {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final drawing = _mode == _EditMode.draw;
          return GestureDetector(
            onPanStart: drawing
                ? (details) => setState(() {
                      _strokes.add(
                          [_normalize(details.localPosition, constraints)]);
                    })
                : null,
            onPanUpdate: drawing
                ? (details) => setState(() {
                      _strokes.last
                          .add(_normalize(details.localPosition, constraints));
                    })
                : null,
            child: Stack(
              children: [
                Image.memory(_bytes),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StrokePainter(_strokes, _ink),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Strokes are kept relative to the picture, so the export does not depend on
  /// the size it was drawn at.
  Offset _normalize(Offset local, BoxConstraints constraints) {
    return Offset(
      (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, this.color);

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * _ImageEditorPageState._strokeFraction;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawPoints(
            ui.PointMode.points,
            [
              Offset(
                  stroke.first.dx * size.width, stroke.first.dy * size.height)
            ],
            paint);
        continue;
      }
      final path = Path();
      for (var i = 0; i < stroke.length; i++) {
        final point =
            Offset(stroke[i].dx * size.width, stroke[i].dy * size.height);
        i == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) =>
      oldDelegate.strokes.length != strokes.length ||
      (strokes.isNotEmpty &&
          oldDelegate.strokes.last.length != strokes.last.length);
}
