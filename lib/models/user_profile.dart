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
