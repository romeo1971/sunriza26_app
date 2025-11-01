import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:sunriza26/services/env_service.dart';

class FactHistoryEntry {
  final String action;
  final int at;
  final String? by;
  final String? note;

  FactHistoryEntry({
    required this.action,
    required this.at,
    this.by,
    this.note,
  });

  factory FactHistoryEntry.fromJson(Map<String, dynamic> json) =>
      FactHistoryEntry(
        action: (json['action'] as String?) ?? 'unknown',
        at: (json['at'] as num?)?.toInt() ?? 0,
        by: json['by'] as String?,
        note: json['note'] as String?,
      );
}

class FactItem {
  final String factId;
  final String factText;
  final double confidence;
  final String scope;
  final String status;
  final int createdAt;
  final int updatedAt;
  final String? authorEmail;
  final String? authorDisplayName;
  final String? authorHash;
  final List<FactHistoryEntry> history;

  FactItem({
    required this.factId,
    required this.factText,
    required this.confidence,
    required this.scope,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.authorEmail,
    this.authorDisplayName,
    this.authorHash,
    required this.history,
  });

  factory FactItem.fromJson(Map<String, dynamic> json) {
    final history =
        (json['history'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(FactHistoryEntry.fromJson)
            .toList() ??
        const [];
    return FactItem(
      factId: (json['fact_id'] as String?) ?? '',
      factText: (json['fact_text'] as String?) ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      scope: (json['scope'] as String?) ?? 'avatar',
      status: (json['status'] as String?) ?? 'pending',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      authorEmail: json['author_email'] as String?,
      authorDisplayName: json['author_display_name'] as String?,
      authorHash: json['author_hash'] as String?,
      history: history,
    );
  }
}

class FactListResponse {
  final List<FactItem> items;
  final bool hasMore;
  final int? nextCursor;

  FactListResponse({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  factory FactListResponse.fromJson(Map<String, dynamic> json) =>
      FactListResponse(
        items:
            (json['items'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(FactItem.fromJson)
                .toList() ??
            const [],
        hasMore: json['has_more'] == true,
        nextCursor: (json['next_cursor'] as num?)?.toInt(),
      );
}

class FactReviewService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<FactListResponse> fetchFacts(
    String avatarId, {
    String status = 'pending',
    int limit = 20,
    int? cursor,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Nicht angemeldet');
    final base = EnvService.pineconeApiBaseUrl();
    if (base.isEmpty) throw Exception('PINECONE_API_BASE_URL fehlt');

    final uri = Uri.parse('$base/avatar/facts/list');
    final body = <String, dynamic>{
      'user_id': user.uid,
      'avatar_id': avatarId,
      'status': status,
      'limit': limit,
    };
    if (cursor != null) body['cursor'] = cursor;

    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final Map<String, dynamic> json =
          jsonDecode(res.body) as Map<String, dynamic>;
      return FactListResponse.fromJson(json);
    }
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }

  Future<FactItem> updateFact(
    String avatarId, {
    required String factId,
    required String newStatus,
    String? note,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Nicht angemeldet');
    final base = EnvService.pineconeApiBaseUrl();
    if (base.isEmpty) throw Exception('PINECONE_API_BASE_URL fehlt');

    final uri = Uri.parse('$base/avatar/facts/update');
    final body = <String, dynamic>{
      'user_id': user.uid,
      'avatar_id': avatarId,
      'fact_id': factId,
      'new_status': newStatus,
      'note': note,
    };

    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final Map<String, dynamic> json =
          jsonDecode(res.body) as Map<String, dynamic>;
      final factJson = json['fact'] as Map<String, dynamic>?;
      if (factJson == null) throw Exception('Antwort ohne Fakt');
      return FactItem.fromJson(factJson);
    }
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
}
