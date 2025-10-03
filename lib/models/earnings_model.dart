import 'package:cloud_firestore/cloud_firestore.dart';

/// Verkaufs-Eintrag (pro Media-Kauf)
class Sale {
  final String id;
  final String sellerId; // User ID (Verkäufer)
  final String avatarId; // Über welchen Avatar verkauft
  final String mediaId; // Welches Media
  final String? mediaName;
  final String buyerId; // Käufer
  final int credits; // Credits bezahlt
  final double amount; // Euro-Wert
  final double platformFee; // Eure Provision
  final double sellerEarnings; // Verkäufer erhält
  final DateTime createdAt;
  final String status; // pending, completed, refunded

  Sale({
    required this.id,
    required this.sellerId,
    required this.avatarId,
    required this.mediaId,
    this.mediaName,
    required this.buyerId,
    required this.credits,
    required this.amount,
    required this.platformFee,
    required this.sellerEarnings,
    required this.createdAt,
    required this.status,
  });

  factory Sale.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Sale.fromMap(doc.id, data);
  }

  factory Sale.fromMap(String id, Map<String, dynamic> map) {
    return Sale(
      id: id,
      sellerId: map['sellerId'] as String,
      avatarId: map['avatarId'] as String,
      mediaId: map['mediaId'] as String,
      mediaName: map['mediaName'] as String?,
      buyerId: map['buyerId'] as String,
      credits: (map['credits'] as num).toInt(),
      amount: (map['amount'] as num).toDouble(),
      platformFee: (map['platformFee'] as num).toDouble(),
      sellerEarnings: (map['sellerEarnings'] as num).toDouble(),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      status: (map['status'] as String?) ?? 'completed',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sellerId': sellerId,
      'avatarId': avatarId,
      'mediaId': mediaId,
      if (mediaName != null) 'mediaName': mediaName,
      'buyerId': buyerId,
      'credits': credits,
      'amount': amount,
      'platformFee': platformFee,
      'sellerEarnings': sellerEarnings,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
    };
  }
}
