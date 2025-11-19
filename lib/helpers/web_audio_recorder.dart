import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

/// External JS functions für Web Audio Recording
@JS('isWebAudioRecordingSupported')
external bool _isWebAudioRecordingSupported();

@JS('startWebAudioRecording')
external JSPromise<_AudioRecordingResult> _startWebAudioRecording();

@JS('stopWebAudioRecording')
external JSPromise<_AudioRecordingResult> _stopWebAudioRecording();

/// JS interop type für Audio Recording Result
extension type _AudioRecordingResult._(JSObject _) implements JSObject {
  external JSBoolean get success;
  external JSString? get error;
  external JSUint8Array? get data;
}

/// Web Audio Recorder Helper für STT.
/// Nutzt die JavaScript MediaRecorder API via dart:js_interop.
class WebAudioRecorder {
  static bool get isSupported {
    if (!kIsWeb) return false;
    try {
      return _isWebAudioRecordingSupported();
    } catch (e) {
      debugPrint('[WebAudioRecorder] isSupported check failed: $e');
      return false;
    }
  }

  /// Startet die Audio-Aufnahme im Browser.
  static Future<bool> start() async {
    if (!kIsWeb) {
      throw UnsupportedError('WebAudioRecorder ist nur auf Web verfügbar');
    }
    try {
      final result = await _startWebAudioRecording().toDart;
      final success = result.success.toDart;
      
      if (!success) {
        final error = result.error?.toDart ?? 'Unknown error';
        debugPrint('[WebAudioRecorder] Start failed: $error');
      }
      return success;
    } catch (e) {
      debugPrint('[WebAudioRecorder] start() exception: $e');
      return false;
    }
  }

  /// Stoppt die Audio-Aufnahme und gibt die Bytes zurück.
  static Future<Uint8List?> stop() async {
    if (!kIsWeb) {
      throw UnsupportedError('WebAudioRecorder ist nur auf Web verfügbar');
    }
    try {
      final result = await _stopWebAudioRecording().toDart;
      final success = result.success.toDart;
      
      if (!success) {
        final error = result.error?.toDart ?? 'Unknown error';
        debugPrint('[WebAudioRecorder] Stop failed: $error');
        return null;
      }
      
      // Extract Uint8Array from result
      final dataJs = result.data;
      if (dataJs == null) {
        debugPrint('[WebAudioRecorder] No data in result');
        return null;
      }
      return dataJs.toDart;
    } catch (e) {
      debugPrint('[WebAudioRecorder] stop() exception: $e');
      return null;
    }
  }
}

