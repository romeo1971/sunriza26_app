import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Live Avatar Tile für bitHuman Agent Generation
class LiveAvatarTile extends StatefulWidget {
  final String? heroImageUrl;
  final String? heroAudioUrl;
  final Function(String model)? onGenerate; // ← Jetzt mit Model parameter!
  final bool isGenerating;
  final String? agentId;

  const LiveAvatarTile({
    super.key,
    this.heroImageUrl,
    this.heroAudioUrl,
    this.onGenerate,
    this.isGenerating = false,
    this.agentId,
  });

  @override
  State<LiveAvatarTile> createState() => _LiveAvatarTileState();
}

class _LiveAvatarTileState extends State<LiveAvatarTile> {
  String _selectedModel = 'essence'; // default: essence

  @override
  Widget build(BuildContext context) {
    final hasHeroImage = widget.heroImageUrl != null && widget.heroImageUrl!.isNotEmpty;
    final hasHeroAudio = widget.heroAudioUrl != null && widget.heroAudioUrl!.isNotEmpty;
    final canGenerate = hasHeroImage && hasHeroAudio && !widget.isGenerating;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.magenta, AppColors.lightBlue],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.face, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Live Avatar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (widget.agentId != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Agent erstellt',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Info: Hero-Image und Hero-Audio erforderlich
          if (!hasHeroImage || !hasHeroAudio)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !hasHeroImage && !hasHeroAudio
                          ? 'Bitte Hero-Image und Hero-Audio hochladen'
                          : !hasHeroImage
                              ? 'Bitte Hero-Image hochladen'
                              : 'Bitte Hero-Audio hochladen',
                      style: const TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hero-Image und Hero-Audio vorhanden',
                      style: TextStyle(color: Colors.green, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Model Toggle
          Row(
            children: [
              const Text(
                'Model:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    _buildModelToggle('essence'),
                    const SizedBox(width: 8),
                    _buildModelToggle('expression'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Generieren Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canGenerate ? () => widget.onGenerate?.call(_selectedModel) : null,
              icon: widget.isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.rocket_launch, size: 18),
              label: Text(
                widget.isGenerating
                    ? 'Generiere Agent...'
                    : widget.agentId != null
                        ? 'Agent neu generieren'
                        : 'Generieren',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: canGenerate
                    ? AppColors.magenta
                    : Colors.white.withValues(alpha: 0.1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                disabledForegroundColor: Colors.white38,
              ),
            ),
          ),

          // Agent ID Anzeige
          if (widget.agentId != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint, color: Colors.white54, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Agent ID: ${widget.agentId}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelToggle(String model) {
    final isSelected = _selectedModel == model;
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() => _selectedModel = model),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [AppColors.magenta, AppColors.lightBlue],
                    )
                  : null,
              color: isSelected ? null : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Center(
              child: Text(
                model,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

