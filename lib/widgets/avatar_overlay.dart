import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ProsodyState {
  double pitch = 0, energy = 0;
  bool speaking = false;
}

class VisemeMixer with ChangeNotifier {
  String a = "Rest", b = "Rest";
  double k = 0.0; // 0..1 mix
  Map<String, Rect> cells;
  VisemeMixer(this.cells);

  void updateWeights(Map<String, double> w) {
    final items = w.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    a = items.isNotEmpty ? items[0].key : "Rest";
    b = items.length > 1 ? items[1].key : a;
    k = items.isNotEmpty ? items[0].value.clamp(0.0, 1.0) : 0.0;
    notifyListeners();
  }
}

class AvatarOverlay extends StatelessWidget {
  final ui.Image atlas;
  final ui.Image mask;
  final Map<String, Rect> cells;
  final Rect roi;
  final VisemeMixer mixer;
  const AvatarOverlay({
    super.key,
    required this.atlas,
    required this.mask,
    required this.cells,
    required this.roi,
    required this.mixer,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Painter(atlas, mask, cells, roi, mixer),
      size: Size.infinite,
      isComplex: true,
      willChange: true,
    );
  }
}

class _Painter extends CustomPainter {
  final ui.Image atlas, mask;
  final Map<String, Rect> cells;
  final Rect roi;
  final VisemeMixer mixer;
  _Painter(this.atlas, this.mask, this.cells, this.roi, this.mixer)
    : super(repaint: mixer);

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    final srcA = cells[mixer.a] ?? cells["Rest"]!;

    // Mask-first: Maske zeichnen, dann Atlas mit srcIn in die Maske
    c.saveLayer(roi, Paint());
    c.drawImageRect(
      mask,
      Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
      roi,
      Paint(),
    );
    c.drawImageRect(atlas, srcA, roi, Paint()..blendMode = BlendMode.srcIn);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}

// Example DataChannel message handlers (wire to flutter_webrtc onDataChannel)
void onVisemeMessage(String jsonStr, VisemeMixer mixer) {
  final m = json.decode(jsonStr) as Map<String, dynamic>;
  final weights = (m["weights"] as Map).map(
    (k, v) => MapEntry(k as String, (v as num).toDouble()),
  );
  mixer.updateWeights(weights);
}

void onProsodyMessage(String jsonStr, ProsodyState state) {
  final m = json.decode(jsonStr) as Map<String, dynamic>;
  state.pitch = (m["pitch"] as num?)?.toDouble() ?? 0.0;
  state.energy = (m["energy"] as num?)?.toDouble() ?? 0.0;
  state.speaking = m["speaking"] == true;
}
