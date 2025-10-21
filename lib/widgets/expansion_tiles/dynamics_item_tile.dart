import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../../theme/app_theme.dart';
import 'expansion_tile_base.dart';

/// Einzelne Dynamics Item ExpansionTile (Basic, Lachen, Herz, etc.)
class DynamicsItemTile extends StatefulWidget {
  final String dynamicsId;
  final String dynamicsName;
  final String? dynamicsIcon;
  final Map<String, dynamic> dynamicsData;
  final String? selectedVideoUrl;
  final bool heroVideoTooLong;
  final bool isGenerating;
  final int timeRemaining;

  // Parameter
  final double drivingMultiplier;
  final double animationScale;
  final int sourceMaxDim; // Nur Anzeige, automatisch berechnet
  final bool flagNormalizeLip;
  final bool flagPasteback;

  // Callbacks
  final VoidCallback onResetDefaults;
  final ValueChanged<double> onDrivingMultiplierChanged;
  final ValueChanged<double> onAnimationScaleChanged;
  // onSourceMaxDimChanged entfernt - Wert wird automatisch berechnet
  final ValueChanged<bool> onFlagNormalizeLipChanged;
  final ValueChanged<bool> onFlagPastebackChanged;
  final VoidCallback onGenerate;
  final VoidCallback onCancelGeneration;
  final VoidCallback? onSelectVideo; // Video wählen
  final VoidCallback? onDeselectVideo; // Video abwählen
  final VoidCallback? onDelete; // Dynamics löschen (nur nicht-Basic)
  final Widget Function({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    String? recommendation,
  })
  buildSlider;
  // Global Toggles (nur sinnvoll für 'basic')
  final bool dynamicsEnabled;
  final bool lipsyncEnabled;
  final ValueChanged<bool> onToggleDynamics;
  final ValueChanged<bool> onToggleLipsync;
  final bool showHeader;

  const DynamicsItemTile({
    super.key,
    required this.dynamicsId,
    required this.dynamicsName,
    this.dynamicsIcon,
    required this.dynamicsData,
    this.selectedVideoUrl,
    this.heroVideoTooLong = false,
    required this.isGenerating,
    required this.timeRemaining,
    required this.drivingMultiplier,
    required this.animationScale,
    required this.sourceMaxDim,
    required this.flagNormalizeLip,
    required this.flagPasteback,
    required this.onResetDefaults,
    required this.onDrivingMultiplierChanged,
    required this.onAnimationScaleChanged,
    // onSourceMaxDimChanged entfernt
    required this.onFlagNormalizeLipChanged,
    required this.onFlagPastebackChanged,
    required this.onGenerate,
    required this.onCancelGeneration,
    this.onSelectVideo,
    this.onDeselectVideo,
    this.onDelete,
    required this.buildSlider,
    required this.dynamicsEnabled,
    required this.lipsyncEnabled,
    required this.onToggleDynamics,
    required this.onToggleLipsync,
    this.showHeader = true,
  });

  @override
  State<DynamicsItemTile> createState() => _DynamicsItemTileState();
}

class _DynamicsItemTileState extends State<DynamicsItemTile> {
  VideoPlayerController? _videoController;
  bool _thumbnailLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadVideoThumbnail();
  }

  @override
  void didUpdateWidget(DynamicsItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Video-Thumbnail neu laden, wenn sich die URL ändert
    if (oldWidget.selectedVideoUrl != widget.selectedVideoUrl) {
      _loadVideoThumbnail();
    }
    // Wenn sich der Status ändert, Widget neu rendern (für Greyscale)
    // UND Video-Thumbnail neu laden, um Greyscale-Effekt anzuwenden
    if (oldWidget.dynamicsData['status'] != widget.dynamicsData['status']) {
      setState(() {});
      // Wenn Video bereits geladen ist, neu rendern reicht
      // Falls nicht geladen, Thumbnail neu laden
      if (_videoController == null && widget.selectedVideoUrl != null) {
        _loadVideoThumbnail();
      }
    }
  }

  Future<void> _loadVideoThumbnail() async {
    if (widget.selectedVideoUrl == null || widget.selectedVideoUrl!.isEmpty) {
      return;
    }

    // Dispose old controller
    _videoController?.dispose();
    setState(() {
      _thumbnailLoaded = false;
    });

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.selectedVideoUrl!),
      );
      await controller.initialize();
      await controller.seekTo(Duration.zero);

      setState(() {
        _videoController = controller;
        _thumbnailLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading video thumbnail: $e');
      setState(() {
        _thumbnailLoaded = false;
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  String _formatCountdown(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '⏳ ${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildGradientSwitch(bool value) {
    return Container(
      width: 48,
      height: 28,
      decoration: BoxDecoration(
        color: value
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: value
                ? const LinearGradient(
                    colors: [AppColors.magenta, AppColors.lightBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: value ? null : Colors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo =
        widget.selectedVideoUrl != null && widget.selectedVideoUrl!.isNotEmpty;

    // Inhalt der Karte als wiederverwendbare Liste
    final List<Widget> children = [
      // Status Badge entfernt
      const SizedBox(height: 8),

      // Video-Auswahl
      // Driving-Label entfernt – spart Platz
      const SizedBox(height: 4),

      if (hasVideo)
        // Video Preview + Placeholder Infotext
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video Thumbnail - Portrait Format 80x120
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 80,
                height: 120,
                color: Colors.black,
                child: Stack(
                  children: [
                    // Echtes Video-Thumbnail - behalte Seitenverhältnis
                    if (_thumbnailLoaded && _videoController != null)
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: widget.dynamicsData['status'] == 'ready'
                                ? VideoPlayer(_videoController!)
                                : ColorFiltered(
                                    colorFilter: const ColorFilter.matrix(
                                      <double>[
                                        0.2126, 0.7152, 0.0722, 0, 0, // Rot
                                        0.2126, 0.7152, 0.0722, 0, 0, // Grün
                                        0.2126, 0.7152, 0.0722, 0, 0, // Blau
                                        0, 0, 0, 1, 0, // Alpha
                                      ],
                                    ),
                                    child: VideoPlayer(_videoController!),
                                  ),
                          ),
                        ),
                      )
                    else
                      // Fallback während Laden
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.grey.shade800,
                              Colors.grey.shade900,
                            ],
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.videocam,
                            color: Colors.white54,
                            size: 40,
                          ),
                        ),
                      ),
                    // Play-Icon Overlay
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Infotext + Generieren/Toggle-Zeile
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Dein Hero-Video gibt die Basis-Bewegungen und -Gestiken Deines Avatars vor.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Generieren (volle Breite)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (hasVideo && !widget.heroVideoTooLong)
                          ? widget.onGenerate
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.magenta,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (b) => const LinearGradient(
                          colors: [AppColors.magenta, AppColors.lightBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(b),
                        child: const Text(
                          'Generieren',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Lipsync Toggle unter Generieren
                  if (widget.dynamicsEnabled)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Lipsync aktiv',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () =>
                                widget.onToggleLipsync(!widget.lipsyncEnabled),
                            child: _buildGradientSwitch(widget.lipsyncEnabled),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (widget.isGenerating)
                    // Generating Status mit Spinner, Countdown + Abbrechen
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.orange),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatCountdown(widget.timeRemaining),
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onCancelGeneration,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                            child: const Text(
                              'Stop',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        )
      else
        // Kein Video gewählt
        OutlinedButton.icon(
          onPressed: widget.onSelectVideo,
          icon: const Icon(Icons.video_library, size: 18),
          label: const Text('Video wählen'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          ),
        ),

      // Löschen-Button für generiertes Basic Dynamics Video - DIREKT unter Generieren
      if (widget.dynamicsId == 'basic' &&
          widget.dynamicsData['status'] == 'ready' &&
          widget.dynamicsData['video_url'] != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Generiertes Video löschen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],

      const SizedBox(height: 16),

      // Parameter Header + Default Button
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Parameter:',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          OutlinedButton(
            onPressed: widget.onResetDefaults,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.grey.shade400,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Standard',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // Sliders
      widget.buildSlider(
        label: 'Expression Strength (Intensität)',
        value: widget.drivingMultiplier,
        min: 0.0,
        max: 1.0,
        divisions: 100,
        onChanged: widget.onDrivingMultiplierChanged,
        valueLabel: widget.drivingMultiplier.toStringAsFixed(2),
        recommendation: '💡 Empfohlen: 0.40-0.42 (natürlich)',
      ),
      const SizedBox(height: 12),

      widget.buildSlider(
        label: 'Animation Scale (Region)',
        value: widget.animationScale,
        min: 1.0,
        max: 2.5,
        divisions: 30,
        onChanged: widget.onAnimationScaleChanged,
        valueLabel: widget.animationScale.toStringAsFixed(2),
        recommendation: '💡 Empfohlen: 2.0 (Gesicht + Hals + Schultern)',
      ),
      const SizedBox(height: 16),

      // Max Dimension - OBSOLETE (nur intern, nicht für User sichtbar)
      // Wert wird automatisch basierend auf Hero-Image-Größe berechnet
      // und direkt im Backend verwendet: ${widget.sourceMaxDim} px
      const SizedBox(height: 8),

      // Toggle-Optionen mit GMBC Gradient
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.magenta.withValues(alpha: 0.15),
              AppColors.lightBlue.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.lightBlue.withValues(alpha: 0.3)),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Erweiterte Optionen:',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Neutralisiere Lächeln - Custom Switch mit GMBC Gradient
              InkWell(
                onTap: () =>
                    widget.onFlagNormalizeLipChanged(!widget.flagNormalizeLip),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Neutralisiere Lächeln',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Schließt Mund im Source-Bild vor Animation',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: _buildGradientSwitch(widget.flagNormalizeLip),
                      ),
                    ],
                  ),
                ),
              ),

              // Körper behalten - Custom Switch mit GMBC Gradient
              InkWell(
                onTap: () =>
                    widget.onFlagPastebackChanged(!widget.flagPasteback),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Körper behalten (Pasteback)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'WICHTIG: Behält vollen Körper + Original-Qualität!',
                              style: TextStyle(
                                color: AppColors.lightBlue.withValues(
                                  alpha: 0.9,
                                ),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: _buildGradientSwitch(widget.flagPasteback),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // Generieren Button ist jetzt oben bei der Video-Section
      // Delete-Button ist auch oben direkt nach Generieren

      // Orange Generating Info Box mit Countdown
      if (widget.isGenerating) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_empty, color: Colors.orange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⏳ Dynamics "${widget.dynamicsName}" wird generiert...',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dauer: ca. 3-4 Minuten (max. 5 Min)',
                      style: TextStyle(
                        color: Colors.orange.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.timeRemaining > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatCountdown(widget.timeRemaining),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],

      // Löschen Button (nur nicht-Basic)
      if (widget.dynamicsId != 'basic' && widget.onDelete != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Dynamics löschen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ];

    if (!widget.showHeader) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    return BaseExpansionTile(
      title: widget.dynamicsName,
      emoji: widget.dynamicsIcon ?? '', // Kein Default-Icon mehr
      initiallyExpanded: widget.dynamicsId == 'basic',
      children: children,
    );
  }
}
