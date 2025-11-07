/// Moment - Gespeicherte Medien-Assets die der User gekauft/angenommen hat
/// Speichert die ORIGINALDATEI (nicht nur Link) unter users/{userId}/moments/
class Moment {
  final String id;
  final String userId;
  final String avatarId;
  final String type; // 'image', 'video', 'audio', 'document'
  final String? mediaId; // Media ID vom Timeline Item
  final String originalUrl; // Original-URL vom Timeline Item
  final String storedUrl; // Gespeicherte URL in Moments
  final String? thumbUrl; // Optional: Thumbnail
  final String? originalFileName;
  final int acquiredAt; // Timestamp wann gekauft/angenommen
  final double? price; // Preis (0.0 = kostenlos)
  final String? currency; // '€' oder '$'
  final String? paymentMethod; // 'free', 'credits', 'stripe'
  final List<String>? tags; // optional: Tags aus Media für Suche/Filter

  const Moment({
    required this.id,
    required this.userId,
    required this.avatarId,
    required this.type,
    this.mediaId,
    required this.originalUrl,
    required this.storedUrl,
    this.thumbUrl,
    this.originalFileName,
    required this.acquiredAt,
    this.price,
    this.currency,
    this.paymentMethod,
    this.tags,
  });

  factory Moment.fromMap(Map<String, dynamic> map) {
    return Moment(
      id: (map['id'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      avatarId: (map['avatarId'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'image',
      mediaId: map['mediaId'] as String?,
      originalUrl: (map['originalUrl'] as String?) ?? '',
      storedUrl: (map['storedUrl'] as String?) ?? '',
      thumbUrl: map['thumbUrl'] as String?,
      originalFileName: map['originalFileName'] as String?,
      acquiredAt: (map['acquiredAt'] as int?) ?? 0,
      price: (map['price'] as num?)?.toDouble(),
      currency: map['currency'] as String?,
      paymentMethod: map['paymentMethod'] as String?,
      tags: (map['tags'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'avatarId': avatarId,
      'type': type,
      if (mediaId != null) 'mediaId': mediaId,
      'originalUrl': originalUrl,
      'storedUrl': storedUrl,
      if (thumbUrl != null) 'thumbUrl': thumbUrl,
      if (originalFileName != null) 'originalFileName': originalFileName,
      'acquiredAt': acquiredAt,
      if (price != null) 'price': price,
      if (currency != null) 'currency': currency,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (tags != null && tags!.isNotEmpty) 'tags': tags,
    };
  }
}
