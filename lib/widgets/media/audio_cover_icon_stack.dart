import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Audio Cover Icon Stack - 5 Icons wie Spielkarten überlappt
/// Farben: white, magenta, white, lightblue, white
class AudioCoverIconStack extends StatelessWidget {
  final List<bool> coverSlots; // 5 Bools: true = Bild vorhanden, false = leer
  final VoidCallback onTap;

  const AudioCoverIconStack({
    super.key,
    required this.coverSlots,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final coverCount = coverSlots.where((e) => e).length;
    
    return Tooltip(
      message: 'Cover Images ($coverCount/5)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 48, // 5 Icons * 8px overlap + 16px letztes Icon
            height: 24,
            child: Stack(
              children: [
                // 5 Karten nebeneinander (überlappt)
                for (int i = 0; i < 5; i++)
                  Positioned(
                    left: i * 8.0, // 8px Overlap
                    child: _buildCard(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(int index) {
    // Farben: white, magenta, white, lightblue, white
    final colors = [
      Colors.white,
      AppColors.magenta,
      Colors.white,
      AppColors.lightBlue,
      Colors.white,
    ];
    
    final color = colors[index];
    final hasImage = index < coverSlots.length && coverSlots[index];
    
    return Container(
      width: 16,
      height: 24,
      decoration: BoxDecoration(
        color: hasImage ? color : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: hasImage
          ? Icon(
              Icons.image,
              size: 10,
              color: (color == Colors.white) ? Colors.black54 : Colors.white,
            )
          : null,
    );
  }
}

