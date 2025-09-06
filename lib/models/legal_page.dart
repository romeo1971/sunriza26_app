class LegalPage {
  final String id;
  final String type; // 'terms', 'imprint', 'privacy'
  final String title;
  final String content;
  final bool isHtml;
  final int createdAt;
  final int updatedAt;
  final String? createdBy; // Admin user ID

  LegalPage({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.isHtml = false,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  factory LegalPage.fromMap(Map<String, dynamic> map) {
    return LegalPage(
      id: map['id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      isHtml: (map['isHtml'] as bool?) ?? false,
      createdAt: (map['createdAt'] as num).toInt(),
      updatedAt: (map['updatedAt'] as num).toInt(),
      createdBy: map['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'content': content,
      'isHtml': isHtml,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'createdBy': createdBy,
    };
  }

  LegalPage copyWith({
    String? title,
    String? content,
    bool? isHtml,
    int? updatedAt,
    String? createdBy,
  }) {
    return LegalPage(
      id: id,
      type: type,
      title: title ?? this.title,
      content: content ?? this.content,
      isHtml: isHtml ?? this.isHtml,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
