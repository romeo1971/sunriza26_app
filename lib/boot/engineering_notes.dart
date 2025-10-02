// Engineering Anchors: zentrale Hinweise, die gezielt bei Fehlern geloggt werden.
// Kontext & Root-Cause-Doku: siehe brain/playlist_crash_root_cause.md

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../utils/playlist_time_utils.dart';

bool _engineeringAnchorPrinted = false;

void _printEngineeringAnchors() {
  if (_engineeringAnchorPrinted) return;
  _engineeringAnchorPrinted = true;
  try {
    final sample = buildSlotSummaryLabel([5, 0]);
    // ignore: avoid_print
    print('🔗 Engineering Docs:');
    // ignore: avoid_print
    print('   📘 brain/docs/firebase_storage_architecture.md');
    // ignore: avoid_print
    print('   📘 brain/incidents/playlist_crash_root_cause.md');
    // ignore: avoid_print
    print(
      'ℹ️ Slot-Merge-Util aktiv (5+0 → $sample): lib/utils/playlist_time_utils.dart',
    );
  } catch (_) {
    // no-op
  }
}

/// Registriert Fehler-Hooks: Bei erstem Flutter-/Plattformfehler werden
/// Engineering-Hinweise geloggt. Optional auch beim Boot (nur Debug).
void registerEngineeringAnchors({bool alwaysLogOnBoot = false}) {
  if (alwaysLogOnBoot && kDebugMode) {
    _printEngineeringAnchors();
  }

  final prevFlutter = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    _printEngineeringAnchors();
    if (prevFlutter != null) {
      prevFlutter(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final prevPlatform = ui.PlatformDispatcher.instance.onError;
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _printEngineeringAnchors();
    _clearPressedKeysSafe();
    if (prevPlatform != null) {
      return prevPlatform(error, stack);
    }
    return false; // Standardverhalten beibehalten
  };
}

/// Öffentlicher Navigator-Observer: leert bei Routenwechseln die gedrückten Tasten,
/// um hängengebliebene KeyDown-Zustände (z. B. 5+0 Wrap-Fall, Fokuswechsel) zu vermeiden.
class EngineeringNavigatorObserver extends NavigatorObserver {
  @override
  void didPop(Route route, Route? previousRoute) {
    _clearPressedKeysSafe();
    super.didPop(route, previousRoute);
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _clearPressedKeysSafe();
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _clearPressedKeysSafe();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

final EngineeringNavigatorObserver engineeringNavigatorObserver =
    EngineeringNavigatorObserver();

void _clearPressedKeysSafe() {
  try {
    // Neuere Flutter-Versionen
    (ServicesBinding.instance.keyboard as dynamic).clearPressedKeys();
  } catch (_) {
    try {
      // Ältere RawKeyboard-API
      (RawKeyboard.instance as dynamic).clearKeysPressed();
    } catch (_) {}
  }
}
