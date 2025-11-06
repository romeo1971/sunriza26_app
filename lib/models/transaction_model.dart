import 'package:cloud_firestore/cloud_firestore.dart';

/// Transaktionstypen
enum TransactionType {
  creditPurchase, // Credits gekauft
  creditSpent, // Credits ausgegeben
  mediaPurchase, // Media direkt gekauft (ohne Credits)
}

/// Media-Typ für Transaktionen
enum PurchasedMediaType {
  image,
  video,
  audio,
  bundle, // Mehrere Medien
}

/// Transaktion Model
class Transaction {
  final String id;
  final String userId;
  final TransactionType type;
  final int? credits; // Credits amount (bei credit-bezogenen Transaktionen)
  final double? amount; // Geld amount in EUR/USD
  final String? currency; // eur, usd
  final double? exchangeRate; // Wechselkurs bei USD
  final String? stripeSessionId; // Stripe Checkout Session ID
  final String? paymentIntent; // Stripe Payment Intent
  final String status; // pending, completed, failed, refunded
  final DateTime createdAt;

  // Für Media-Käufe
  final String? mediaId; // ID des gekauften Mediums
  final PurchasedMediaType? mediaType; // Typ des Mediums
  final String? mediaUrl; // URL des Mediums
  final String? mediaName; // Name des Mediums
  final String? avatarId; // Avatar dem das Medium gehört
  final List<String>? mediaIds; // Bei Bundle: Mehrere Media IDs

  // Rechnungs-Daten
  final String? invoiceNumber; // Rechnungsnummer
  final String? invoicePdfUrl; // URL zur PDF-Rechnung
  // Nachweis-Status (OTS): pending | stamped | stored | not_anchored | error
  final String? anchorStatus;

  Transaction({
    required this.id,
    required this.userId,
    required this.type,
    this.credits,
    this.amount,
    this.currency,
    this.exchangeRate,
    this.stripeSessionId,
    this.paymentIntent,
    required this.status,
    required this.createdAt,
    this.mediaId,
    this.mediaType,
    this.mediaUrl,
    this.mediaName,
    this.avatarId,
    this.mediaIds,
    this.invoiceNumber,
    this.invoicePdfUrl,
    this.anchorStatus,
  });

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Transaction.fromMap(doc.id, data);
  }

  factory Transaction.fromMap(String id, Map<String, dynamic> map) {
    // Parse TransactionType
    TransactionType type;
    switch (map['type'] as String?) {
      case 'credit_purchase':
        type = TransactionType.creditPurchase;
        break;
      case 'credit_spent':
        type = TransactionType.creditSpent;
        break;
      case 'media_purchase':
        type = TransactionType.mediaPurchase;
        break;
      default:
        type = TransactionType.creditPurchase;
    }

    // Parse PurchasedMediaType
    PurchasedMediaType? mediaType;
    if (map['mediaType'] != null) {
      switch (map['mediaType'] as String) {
        case 'image':
          mediaType = PurchasedMediaType.image;
          break;
        case 'video':
          mediaType = PurchasedMediaType.video;
          break;
        case 'audio':
          mediaType = PurchasedMediaType.audio;
          break;
        case 'bundle':
          mediaType = PurchasedMediaType.bundle;
          break;
      }
    }

    return Transaction(
      id: id,
      userId: map['userId'] as String,
      type: type,
      credits: (map['credits'] as num?)?.toInt(),
      amount: (map['amount'] as num?)?.toDouble(),
      currency: map['currency'] as String?,
      exchangeRate: (map['exchangeRate'] as num?)?.toDouble(),
      stripeSessionId: map['stripeSessionId'] as String?,
      paymentIntent: map['paymentIntent'] as String?,
      status: (map['status'] as String?) ?? 'pending',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      mediaId: map['mediaId'] as String?,
      mediaType: mediaType,
      mediaUrl: map['mediaUrl'] as String?,
      mediaName: map['mediaName'] as String?,
      avatarId: map['avatarId'] as String?,
      mediaIds: (map['mediaIds'] as List<dynamic>?)?.cast<String>(),
      invoiceNumber: map['invoiceNumber'] as String?,
      invoicePdfUrl: map['invoicePdfUrl'] as String?,
      anchorStatus: map['anchorStatus'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    String typeStr;
    switch (type) {
      case TransactionType.creditPurchase:
        typeStr = 'credit_purchase';
        break;
      case TransactionType.creditSpent:
        typeStr = 'credit_spent';
        break;
      case TransactionType.mediaPurchase:
        typeStr = 'media_purchase';
        break;
    }

    String? mediaTypeStr;
    if (mediaType != null) {
      switch (mediaType!) {
        case PurchasedMediaType.image:
          mediaTypeStr = 'image';
          break;
        case PurchasedMediaType.video:
          mediaTypeStr = 'video';
          break;
        case PurchasedMediaType.audio:
          mediaTypeStr = 'audio';
          break;
        case PurchasedMediaType.bundle:
          mediaTypeStr = 'bundle';
          break;
      }
    }

    return {
      'userId': userId,
      'type': typeStr,
      if (credits != null) 'credits': credits,
      if (amount != null) 'amount': amount,
      if (currency != null) 'currency': currency,
      if (exchangeRate != null) 'exchangeRate': exchangeRate,
      if (stripeSessionId != null) 'stripeSessionId': stripeSessionId,
      if (paymentIntent != null) 'paymentIntent': paymentIntent,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      if (mediaId != null) 'mediaId': mediaId,
      if (mediaTypeStr != null) 'mediaType': mediaTypeStr,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaName != null) 'mediaName': mediaName,
      if (avatarId != null) 'avatarId': avatarId,
      if (mediaIds != null) 'mediaIds': mediaIds,
      if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
      if (invoicePdfUrl != null) 'invoicePdfUrl': invoicePdfUrl,
      if (anchorStatus != null) 'anchorStatus': anchorStatus,
    };
  }

  /// Betrag in Hauptwährungseinheit (z. B. EUR) – Firestore speichert Cents
  double get amountMajorUnit => (amount ?? 0.0) / 100.0;

  /// Formatiert Betrag für Anzeige (aus Cents → EUR/USD)
  String get formattedAmount {
    final symbol = currency == 'usd' ? '\$' : '€';
    return '${amountMajorUnit.toStringAsFixed(2)} $symbol';
  }

  /// Formatiert Credits für Anzeige
  String get formattedCredits {
    if (credits == null) return '-';
    return '$credits 💎';
  }

  /// Icon basierend auf Transaktionstyp
  String get typeIcon {
    switch (type) {
      case TransactionType.creditPurchase:
        return '💳';
      case TransactionType.creditSpent:
        return '💎';
      case TransactionType.mediaPurchase:
        return '🖼️';
    }
  }

  /// Beschreibung basierend auf Typ
  String get typeDescription {
    switch (type) {
      case TransactionType.creditPurchase:
        return 'Credits gekauft';
      case TransactionType.creditSpent:
        return mediaName ?? 'Media freigeschaltet';
      case TransactionType.mediaPurchase:
        return mediaName ?? 'Media gekauft';
    }
  }
}
