import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class LocalizationService extends ChangeNotifier {
  String? _loadedCode;
  Map<String, String> _strings = {};

  String? _previewCode;
  Map<String, String>? _previewStrings;

  String get activeCode => _previewCode ?? _loadedCode ?? 'en';

  String t(String key, {Map<String, String>? params}) {
    final table = _previewStrings ?? _strings;
    var value = table[key] ?? key;
    if (params != null) {
      params.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }

  Future<void> useLanguageCode(String? code) async {
    final target = (code == null || code.isEmpty) ? 'en' : code;
    if (_loadedCode == target && _previewCode == null) return;
    _loadedCode = target;
    _strings = await _loadJsonFor(target);
    _previewCode = null;
    _previewStrings = null;
    notifyListeners();
  }

  Future<void> setPreviewLanguage(String code) async {
    if (_previewCode == code) return;
    _previewCode = code;
    _previewStrings = await _loadJsonFor(code);
    notifyListeners();
  }

  void clearPreview() {
    if (_previewCode == null) return;
    _previewCode = null;
    _previewStrings = null;
    notifyListeners();
  }

  Future<Map<String, String>> _loadJsonFor(String code) async {
    final candidates = <String>[
      'assets/lang/$code.json',
      'assets/lang/${code.split('-').first}.json',
      'assets/lang/en.json',
    ];
    for (final path in candidates) {
      try {
        final data = await rootBundle.loadString(path);
        final Map<String, dynamic> jsonMap = json.decode(data);
        return jsonMap.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {
        // try next
      }
    }
    return {};
  }
}
