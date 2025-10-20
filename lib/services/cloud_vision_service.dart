import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:googleapis/vision/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CloudVisionService {
  static final CloudVisionService _instance = CloudVisionService._internal();
  factory CloudVisionService() => _instance;
  CloudVisionService._internal();

  VisionApi? _visionApi;
  bool _initialized = false;
  bool _useCloudAPI = false; // Fallback auf lokale ML Kit

  /// Initialisiert die Vision API (muss vor erster Verwendung aufgerufen werden)
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // API Key aus .env laden
      final apiKey = dotenv.env['GOOGLE_CLOUD_VISION_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('GOOGLE_CLOUD_VISION_API_KEY fehlt in .env');
      }

      final authClient = clientViaApiKey(apiKey);

      _visionApi = VisionApi(authClient);
      _useCloudAPI = true;
      _initialized = true;
      debugPrint('✅ Google Cloud Vision API mit API Key initialisiert');
    } catch (e) {
      debugPrint('❌ Fehler bei Vision API Initialisierung: $e');
      debugPrint('💡 Verwende lokale ML Kit als Fallback');
      _useCloudAPI = false;
      _initialized = true;
    }
  }

  /// Analysiert ein Bild mit Google Cloud Vision API
  Future<List<String>> analyzeImage(String imagePath) async {
    if (!_initialized) await initialize();

    // Cloud API verwenden - KEIN Fallback!
    if (!_useCloudAPI || _visionApi == null) {
      debugPrint('❌ Cloud API nicht verfügbar - KEINE Tags');
      return [];
    }

    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final request = BatchAnnotateImagesRequest(
        requests: [
          AnnotateImageRequest(
            image: Image(content: base64Image),
            features: [
              // Alle Features für maximale Erkennung
              Feature(type: 'LABEL_DETECTION', maxResults: 50),
              Feature(type: 'OBJECT_LOCALIZATION', maxResults: 50),
              Feature(type: 'FACE_DETECTION', maxResults: 50),
              Feature(type: 'TEXT_DETECTION', maxResults: 50),
              Feature(type: 'DOCUMENT_TEXT_DETECTION', maxResults: 50),
              Feature(type: 'SAFE_SEARCH_DETECTION', maxResults: 10),
              Feature(type: 'IMAGE_PROPERTIES', maxResults: 10),
              Feature(type: 'CROP_HINTS', maxResults: 10),
              Feature(type: 'WEB_DETECTION', maxResults: 50),
              Feature(type: 'PRODUCT_SEARCH', maxResults: 50),
              Feature(type: 'LANDMARK_DETECTION', maxResults: 50),
              Feature(type: 'LOGO_DETECTION', maxResults: 50),
            ],
          ),
        ],
      );

      final response = await _visionApi!.images.annotate(request);
      final annotations = response.responses?.first;

      if (annotations == null) return [];

      final allTags = <String>[];

      // Label Detection - Allgemeine Objekte und Szenen
      if (annotations.labelAnnotations != null) {
        for (final label in annotations.labelAnnotations!) {
          if (label.description != null &&
              label.score != null &&
              label.score! > 0.5) {
            allTags.add(label.description!.toLowerCase());
          }
        }
      }

      // Object Detection - Spezifische Objekte
      if (annotations.localizedObjectAnnotations != null) {
        for (final obj in annotations.localizedObjectAnnotations!) {
          if (obj.name != null) {
            allTags.add(obj.name!.toLowerCase());
          }
        }
      }

      // Face Detection - Gesichter und Emotionen
      if (annotations.faceAnnotations != null) {
        for (final face in annotations.faceAnnotations!) {
          allTags.add('face');
          allTags.add('person');

          // Emotionen basierend auf Gesichtsausdruck
          if (face.joyLikelihood != null) {
            switch (face.joyLikelihood) {
              case 'VERY_LIKELY':
              case 'LIKELY':
                allTags.add('happy');
                allTags.add('smiling');
                break;
            }
          }

          if (face.sorrowLikelihood != null) {
            switch (face.sorrowLikelihood) {
              case 'VERY_LIKELY':
              case 'LIKELY':
                allTags.add('sad');
                allTags.add('crying');
                break;
            }
          }

          if (face.angerLikelihood != null) {
            switch (face.angerLikelihood) {
              case 'VERY_LIKELY':
              case 'LIKELY':
                allTags.add('angry');
                allTags.add('mad');
                break;
            }
          }

          if (face.surpriseLikelihood != null) {
            switch (face.surpriseLikelihood) {
              case 'VERY_LIKELY':
              case 'LIKELY':
                allTags.add('surprised');
                allTags.add('shocked');
                break;
            }
          }

          // Kopfbedeckung
          if (face.headwearLikelihood != null) {
            switch (face.headwearLikelihood) {
              case 'VERY_LIKELY':
              case 'LIKELY':
                allTags.add('hat');
                allTags.add('headwear');
                break;
            }
          }
        }
      }

      // Text Detection - Erkannte Texte
      if (annotations.textAnnotations != null) {
        for (final text in annotations.textAnnotations!) {
          if (text.description != null) {
            final textLower = text.description!.toLowerCase();
            allTags.add('text');

            // Spezifische Text-Erkennung
            if (textLower.contains('frau') || textLower.contains('woman')) {
              allTags.addAll(['woman', 'female', 'lady']);
            }
            if (textLower.contains('mann') || textLower.contains('man')) {
              allTags.addAll(['man', 'male', 'guy']);
            }
            if (textLower.contains('hut') || textLower.contains('hat')) {
              allTags.addAll(['hat', 'headwear']);
            }
          }
        }
      }

      // Safe Search - Explizite Inhalte
      if (annotations.safeSearchAnnotation != null) {
        final safeSearch = annotations.safeSearchAnnotation!;

        if (safeSearch.adult != null) {
          switch (safeSearch.adult) {
            case 'VERY_LIKELY':
            case 'LIKELY':
              allTags.addAll(['adult', 'nude', 'naked']);
              break;
          }
        }

        if (safeSearch.racy != null) {
          switch (safeSearch.racy) {
            case 'VERY_LIKELY':
            case 'LIKELY':
              allTags.addAll(['racy', 'suggestive', 'sexy']);
              break;
          }
        }

        if (safeSearch.violence != null) {
          switch (safeSearch.violence) {
            case 'VERY_LIKELY':
            case 'LIKELY':
              allTags.addAll(['violence', 'blood', 'weapon']);
              break;
          }
        }

        if (safeSearch.medical != null) {
          switch (safeSearch.medical) {
            case 'VERY_LIKELY':
            case 'LIKELY':
              allTags.addAll(['medical', 'injury', 'sick']);
              break;
          }
        }
      }

      // Web Detection - Ähnliche Bilder und Entitäten
      if (annotations.webDetection != null) {
        final webDetection = annotations.webDetection!;

        if (webDetection.webEntities != null) {
          for (final entity in webDetection.webEntities!) {
            if (entity.description != null &&
                entity.score != null &&
                entity.score! > 0.5) {
              allTags.add(entity.description!.toLowerCase());
            }
          }
        }

        if (webDetection.bestGuessLabels != null) {
          for (final label in webDetection.bestGuessLabels!) {
            if (label.label != null) {
              allTags.add(label.label!.toLowerCase());
            }
          }
        }
      }

      // Manuelle Tag-Ergänzungen basierend auf erkannten Tags
      if (allTags.any(
        (tag) => tag.contains('person') || tag.contains('face'),
      )) {
        // Wenn Personen erkannt werden, füge häufige Kleidungs-Tags hinzu
        if (allTags.any(
          (tag) => tag.contains('jacket') || tag.contains('coat'),
        )) {
          allTags.add('jacket');
          allTags.add('outerwear');
        }
        if (allTags.any(
          (tag) => tag.contains('shirt') || tag.contains('blouse'),
        )) {
          allTags.add('shirt');
          allTags.add('top');
        }
        if (allTags.any((tag) => tag.contains('hat') || tag.contains('cap'))) {
          allTags.add('hat');
          allTags.add('headwear');
        }

        // Zähle Personen
        final personTags = allTags
            .where(
              (tag) =>
                  tag.contains('person') ||
                  tag.contains('face') ||
                  tag.contains('woman') ||
                  tag.contains('man'),
            )
            .toList();

        if (personTags.length >= 2) {
          allTags.add('multiple people');
          allTags.add('group');
        }
      }

      // Duplikate entfernen und zurückgeben
      final uniqueTags = allTags.toSet().toList();
      debugPrint(
        '🔍 Cloud Vision API Tags gefunden: ${uniqueTags.length} - $uniqueTags',
      );
      return uniqueTags;
    } catch (e) {
      debugPrint('❌ Fehler bei Bildanalyse: $e');
      return [];
    }
  }

  /// Prüft ob ein Suchbegriff zu den Bild-Tags passt
  bool matchesSearch(List<String> imageTags, String searchTerm) {
    if (searchTerm.isEmpty) return true;

    final searchLower = searchTerm.toLowerCase();

    // 1. Direkte Suche nach dem kompletten Suchbegriff (z.B. "black jacket")
    if (imageTags.any((tag) => tag.contains(searchLower))) {
      return true;
    }

    // 2. Suche nach einzelnen Keywords
    final keywords = searchLower.split(' ');

    for (final keyword in keywords) {
      // Direkte Tag-Suche
      if (imageTags.any((tag) => tag.contains(keyword))) {
        return true;
      }

      // Erweiterte KI-Logik für explizite Suchbegriffe
      if (keyword.contains('frau') ||
          keyword.contains('woman') ||
          keyword.contains('female')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('woman') ||
              tag.contains('female') ||
              tag.contains('lady') ||
              tag.contains('girl') ||
              tag.contains('person') ||
              tag.contains('face'),
        )) {
          return true;
        }
      }

      // Spezielle Logik für "2 woman" oder "zwei frauen"
      if (searchLower.contains('2 woman') ||
          searchLower.contains('zwei frauen') ||
          searchLower.contains('two women')) {
        // Zähle wie viele Personen im Bild sind
        final personCount = imageTags
            .where(
              (tag) =>
                  tag.contains('person') ||
                  tag.contains('face') ||
                  tag.contains('woman') ||
                  tag.contains('man'),
            )
            .length;

        if (personCount >= 2) {
          return true;
        }
      }

      if (keyword.contains('mann') ||
          keyword.contains('man') ||
          keyword.contains('male')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('man') ||
              tag.contains('male') ||
              tag.contains('guy') ||
              tag.contains('boy') ||
              tag.contains('person') ||
              tag.contains('face'),
        )) {
          return true;
        }
      }

      if (keyword.contains('nackt') ||
          keyword.contains('nude') ||
          keyword.contains('naked')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('nude') ||
              tag.contains('adult') ||
              tag.contains('naked'),
        )) {
          return true;
        }
      }

      if (keyword.contains('sex') || keyword.contains('sexual')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('adult') ||
              tag.contains('racy') ||
              tag.contains('suggestive'),
        )) {
          return true;
        }
      }

      if (keyword.contains('hut') || keyword.contains('hat')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('hat') ||
              tag.contains('headwear') ||
              tag.contains('cap'),
        )) {
          return true;
        }
      }

      if (keyword.contains('blut') || keyword.contains('blood')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('blood') ||
              tag.contains('violence') ||
              tag.contains('red'),
        )) {
          return true;
        }
      }

      if (keyword.contains('penis') || keyword.contains('dick')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('adult') ||
              tag.contains('nude') ||
              tag.contains('genital'),
        )) {
          return true;
        }
      }

      if (keyword.contains('anal') || keyword.contains('analverkehr')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('adult') ||
              tag.contains('racy') ||
              tag.contains('sexual'),
        )) {
          return true;
        }
      }

      if (keyword.contains('hund') ||
          keyword.contains('dog') ||
          keyword.contains('hunde')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('dog') ||
              tag.contains('puppy') ||
              tag.contains('canine') ||
              tag.contains('pet') ||
              tag.contains('animal'),
        )) {
          return true;
        }
      }

      if (keyword.contains('gänseblümchen') || keyword.contains('daisy')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('flower') ||
              tag.contains('daisy') ||
              tag.contains('plant'),
        )) {
          return true;
        }
      }

      if (keyword.contains('auto') || keyword.contains('car')) {
        if (imageTags.any(
          (tag) =>
              tag.contains('car') ||
              tag.contains('vehicle') ||
              tag.contains('automobile'),
        )) {
          return true;
        }
      }
    }

    return false;
  }

  /// Test-Funktion für die Vision API
  Future<void> testVisionAPI() async {
    debugPrint('🧪 Teste Google Cloud Vision API...');

    if (!_initialized) {
      await initialize();
    }

    if (_useCloudAPI) {
      debugPrint('✅ Google Cloud Vision API ist bereit!');
      debugPrint('🔍 Lade ein Bild hoch um die KI-Tags zu sehen');
    } else {
      debugPrint('❌ Google Cloud Vision API ist nicht verfügbar');
      debugPrint('💡 Bitte folge der Anleitung in GOOGLE_CLOUD_SETUP.md');
    }
  }
}
