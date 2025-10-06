import 'package:flutter/material.dart';

class SafeNetworkImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? error;

  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.error,
  });

  bool get _isEmpty => url == null || url!.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: Colors.grey.shade800,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image, color: Colors.white54),
    );

    if (_isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: placeholder ?? fallback,
      );
    }

    return Image.network(
      url!,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          SizedBox(width: width, height: height, child: error ?? fallback),
    );
  }
}
