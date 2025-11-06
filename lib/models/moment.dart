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
  final String? receiptId; // Link zur Rechnung (falls gekauft)
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
    this.receiptId,
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
      receiptId: map['receiptId'] as String?,
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
      if (receiptId != null) 'receiptId': receiptId,
      if (tags != null && tags!.isNotEmpty) 'tags': tags,
    };
  }
}

/// Receipt - Kauf-/Download-Beleg für Moments
class Receipt {
  final String id;
  final String userId;
  final String avatarId;
  final String momentId; // Link zum Moment
  final double price;
  final String currency;
  final String paymentMethod; // 'stripe', 'credits', 'free'
  final int createdAt;
  final String? stripePaymentIntentId; // Optional: Stripe Payment Intent
  final Map<String, dynamic>? metadata; // Optional: Zusatzinfos

  const Receipt({
    required this.id,
    required this.userId,
    required this.avatarId,
    required this.momentId,
    required this.price,
    required this.currency,
    required this.paymentMethod,
    required this.createdAt,
    this.stripePaymentIntentId,
    this.metadata,
  });

  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      id: (map['id'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      avatarId: (map['avatarId'] as String?) ?? '',
      momentId: (map['momentId'] as String?) ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      currency: (map['currency'] as String?) ?? '€',
      paymentMethod: (map['paymentMethod'] as String?) ?? 'free',
      createdAt: (map['createdAt'] as int?) ?? 0,
      stripePaymentIntentId: map['stripePaymentIntentId'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'avatarId': avatarId,
      'momentId': momentId,
      'price': price,
      'currency': currency,
      'paymentMethod': paymentMethod,
      'createdAt': createdAt,
      if (stripePaymentIntentId != null) 'stripePaymentIntentId': stripePaymentIntentId,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

