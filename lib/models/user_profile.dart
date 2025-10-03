class UserProfile {
  final String uid;
  final String? email;
  final String? displayName;
  final String? profileImageUrl;
  final bool isOnboarded;
  final int createdAt;
  final int updatedAt;

  // Erweiterte Profildaten
  final String? firstName;
  final String? lastName;
  final String? street;
  final String? city;
  final String? postalCode;
  final String? country;
  final String? phoneNumber;
  final bool phoneVerified;
  final String? stripeCustomerId;
  final String? defaultPaymentMethodId;
  // Appsprache des Users (z. B. 'de', 'en', 'zh-Hans')
  final String? language;
  // Geburtsdatum (Date of Birth) in Millisekunden seit Epoch
  final int? dob;
  // Credits-System
  final int credits; // Verfügbare Credits
  final int creditsPurchased; // Gesamt gekaufte Credits
  final int creditsSpent; // Gesamt ausgegebene Credits

  // Seller/Marketplace (Stripe Connect)
  final bool isSeller; // Verkauft der User Media?
  final String? stripeConnectAccountId; // Connected Account ID
  final String? stripeConnectStatus; // pending, active, restricted, disabled
  final bool payoutsEnabled; // Auszahlungen aktiviert?
  final double pendingEarnings; // Noch nicht ausgezahlte Einnahmen (€)
  final double totalEarnings; // Gesamt verdient (€)
  final int? lastPayoutDate; // Letzte Auszahlung (Timestamp)

  // Business-Daten (optional, nur für Seller)
  final String? businessName; // Firmenname
  final String? businessEmail; // Geschäftliche E-Mail
  final String? businessPhone; // Geschäftliche Telefonnummer
  final String? businessStreet; // Geschäftsadresse
  final String? businessCity;
  final String? businessPostalCode;
  final String? businessCountry;
  final String? taxId; // Steuernummer/USt-ID
  final String? businessType; // individual, company

  UserProfile({
    required this.uid,
    this.email,
    this.displayName,
    this.profileImageUrl,
    this.isOnboarded = false,
    required this.createdAt,
    required this.updatedAt,
    // Erweiterte Felder
    this.firstName,
    this.lastName,
    this.street,
    this.city,
    this.postalCode,
    this.country,
    this.phoneNumber,
    this.phoneVerified = false,
    this.stripeCustomerId,
    this.defaultPaymentMethodId,
    this.language,
    this.dob,
    this.credits = 0,
    this.creditsPurchased = 0,
    this.creditsSpent = 0,
    this.isSeller = false,
    this.stripeConnectAccountId,
    this.stripeConnectStatus,
    this.payoutsEnabled = false,
    this.pendingEarnings = 0.0,
    this.totalEarnings = 0.0,
    this.lastPayoutDate,
    this.businessName,
    this.businessEmail,
    this.businessPhone,
    this.businessStreet,
    this.businessCity,
    this.businessPostalCode,
    this.businessCountry,
    this.taxId,
    this.businessType,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] as String,
      email: map['email'] as String?,
      displayName: map['displayName'] as String?,
      profileImageUrl: map['profileImageUrl'] as String?,
      isOnboarded: (map['isOnboarded'] as bool?) ?? false,
      createdAt: (map['createdAt'] as num).toInt(),
      updatedAt: (map['updatedAt'] as num).toInt(),
      // Erweiterte Felder
      firstName: map['firstName'] as String?,
      lastName: map['lastName'] as String?,
      street: map['street'] as String?,
      city: map['city'] as String?,
      postalCode: map['postalCode'] as String?,
      country: map['country'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      phoneVerified: (map['phoneVerified'] as bool?) ?? false,
      stripeCustomerId: map['stripeCustomerId'] as String?,
      defaultPaymentMethodId: map['defaultPaymentMethodId'] as String?,
      language: map['language'] as String?,
      dob: map['dob'] as int?,
      credits: (map['credits'] as num?)?.toInt() ?? 0,
      creditsPurchased: (map['creditsPurchased'] as num?)?.toInt() ?? 0,
      creditsSpent: (map['creditsSpent'] as num?)?.toInt() ?? 0,
      isSeller: (map['isSeller'] as bool?) ?? false,
      stripeConnectAccountId: map['stripeConnectAccountId'] as String?,
      stripeConnectStatus: map['stripeConnectStatus'] as String?,
      payoutsEnabled: (map['payoutsEnabled'] as bool?) ?? false,
      pendingEarnings: (map['pendingEarnings'] as num?)?.toDouble() ?? 0.0,
      totalEarnings: (map['totalEarnings'] as num?)?.toDouble() ?? 0.0,
      lastPayoutDate: map['lastPayoutDate'] as int?,
      businessName: map['businessName'] as String?,
      businessEmail: map['businessEmail'] as String?,
      businessPhone: map['businessPhone'] as String?,
      businessStreet: map['businessStreet'] as String?,
      businessCity: map['businessCity'] as String?,
      businessPostalCode: map['businessPostalCode'] as String?,
      businessCountry: map['businessCountry'] as String?,
      taxId: map['taxId'] as String?,
      businessType: map['businessType'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'profileImageUrl': profileImageUrl,
      'isOnboarded': isOnboarded,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      // Erweiterte Felder
      'firstName': firstName,
      'lastName': lastName,
      'street': street,
      'city': city,
      'postalCode': postalCode,
      'country': country,
      'phoneNumber': phoneNumber,
      'phoneVerified': phoneVerified,
      'stripeCustomerId': stripeCustomerId,
      'defaultPaymentMethodId': defaultPaymentMethodId,
      'language': language,
      'dob': dob,
      'credits': credits,
      'creditsPurchased': creditsPurchased,
      'creditsSpent': creditsSpent,
      'isSeller': isSeller,
      if (stripeConnectAccountId != null)
        'stripeConnectAccountId': stripeConnectAccountId,
      if (stripeConnectStatus != null)
        'stripeConnectStatus': stripeConnectStatus,
      'payoutsEnabled': payoutsEnabled,
      'pendingEarnings': pendingEarnings,
      'totalEarnings': totalEarnings,
      if (lastPayoutDate != null) 'lastPayoutDate': lastPayoutDate,
      if (businessName != null) 'businessName': businessName,
      if (businessEmail != null) 'businessEmail': businessEmail,
      if (businessPhone != null) 'businessPhone': businessPhone,
      if (businessStreet != null) 'businessStreet': businessStreet,
      if (businessCity != null) 'businessCity': businessCity,
      if (businessPostalCode != null) 'businessPostalCode': businessPostalCode,
      if (businessCountry != null) 'businessCountry': businessCountry,
      if (taxId != null) 'taxId': taxId,
      if (businessType != null) 'businessType': businessType,
    };
  }

  UserProfile copyWith({
    String? email,
    String? displayName,
    String? profileImageUrl,
    bool? isOnboarded,
    int? createdAt,
    int? updatedAt,
    String? firstName,
    String? lastName,
    String? street,
    String? city,
    String? postalCode,
    String? country,
    String? phoneNumber,
    bool? phoneVerified,
    String? stripeCustomerId,
    String? defaultPaymentMethodId,
    String? language,
    int? dob,
  }) {
    return UserProfile(
      uid: uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      street: street ?? this.street,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      defaultPaymentMethodId:
          defaultPaymentMethodId ?? this.defaultPaymentMethodId,
      language: language ?? this.language,
      dob: dob ?? this.dob,
    );
  }
}
