import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import '../../../theme/app_theme.dart';

/// Video Media Section für Details Screen
///
/// Vollständig extrahierte, modulare Widget-Sektion für den Video-Bereich.
/// Zeigt Hero-Video links und Galerie rechts.
///
/// Verwendung:
/// ```dart
/// DetailsVideoMediaSection(
///   // Videos
///   videoUrls: _videoUrls,
///   inlineVideoController: _inlineVideoController,
///
///   // Audio State
///   videoAudioEnabled: _videoAudioEnabled,
///
///   // Delete Mode
///   isDeleteMode: _isDeleteMode,
///   selectedRemoteVideos: _selectedRemoteVideos,
///   selectedLocalVideos: _selectedLocalVideos,
///
///   // Callbacks
///   getHeroVideoUrl: _getHeroVideoUrl,
///   playNetworkInline: _playNetworkInline,
///   thumbnailForRemote: _thumbnailForRemote,
///   toggleVideoAudio: _toggleVideoAudio,
///   setHeroVideo: _setHeroVideo,
///   onDeleteModeCancel: () { setState(() { _isDeleteMode = false; _selectedRemoteVideos.clear(); _selectedLocalVideos.clear(); }); },
///   onDeleteConfirm: _confirmDeleteSelectedImages,
///   onTrashIconTap: (url) { setState(() { _isDeleteMode = true; if (_selectedRemoteVideos.contains(url)) { _selectedRemoteVideos.remove(url); } else { _selectedRemoteVideos.add(url); } }); },
///
///   // Video Controller Helpers
///   videoControllerForThumb: _videoControllerForThumb,
/// )
/// ```
class DetailsVideoMediaSection extends StatelessWidget {
  // Videos
  final List<String> videoUrls;
  final VideoPlayerController? inlineVideoController;

  // Audio State (Map: URL -> bool)
  final Map<String, bool> videoAudioEnabled;

  // Delete Mode
  final bool isDeleteMode;
  final Set<String> selectedRemoteVideos;
  final Set<String> selectedLocalVideos;

  // Callbacks
  final String? Function() getHeroVideoUrl;
  final Future<void> Function(String url) playNetworkInline;
  final Future<Uint8List?> Function(String url) thumbnailForRemote;
  final ValueChanged<String> toggleVideoAudio;
  final ValueChanged<String> setHeroVideo;
  // Original-Dateiname Resolver
  final String Function(String url) fileNameFromUrl;
  final VoidCallback onDeleteModeCancel;
  final VoidCallback onDeleteConfirm;
  final ValueChanged<String> onTrashIconTap; // (url) => { setState... }

  // Trim Callbacks (optional)
  final VoidCallback? onTrimHeroVideo;
  final ValueChanged<String>? onTrimVideo;

  // Video Controller Helper
  final Future<VideoPlayerController?> Function(String url)
  videoControllerForThumb;

  // Optional: Mapping URL -> thumbUrl aus Media-Dokumenten (Backend-Thumbs)
  final String? Function(String url)? thumbUrlForMedia;

  const DetailsVideoMediaSection({
    super.key,
    required this.videoUrls,
    required this.inlineVideoController,
    required this.videoAudioEnabled,
    required this.isDeleteMode,
    required this.selectedRemoteVideos,
    required this.selectedLocalVideos,
    required this.getHeroVideoUrl,
    required this.playNetworkInline,
    required this.thumbnailForRemote,
    required this.toggleVideoAudio,
    required this.setHeroVideo,
    required this.onDeleteModeCancel,
    required this.onDeleteConfirm,
    required this.onTrashIconTap,
    required this.videoControllerForThumb,
    required this.fileNameFromUrl,
    this.onTrimHeroVideo,
    this.onTrimVideo,
    this.thumbUrlForMedia,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> remoteFour = videoUrls.take(15).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          const double spacing = 16.0;
          const double gridSpacing = 12.0;
          const double navBtnH = 40.0;
          // MASTER: Image-Größe (wie in details_image_media_section.dart)
          const double leftH = 223.0;
          final double leftW = leftH * (9 / 16);
          const double totalH = leftH;

          return SizedBox(
            width: cons.maxWidth, // Volle Breite nutzen wie bei Images
            height: totalH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Video-Preview/Inline-Player links GROSS
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: leftW,
                      height: leftH,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFE91E63),
                              AppColors.lightBlue,
                              Color(0xFF00E5FF),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              // Video (gecroppt auf Container-Größe)
                              if (inlineVideoController != null)
                                Positioned.fill(
                                  child: ClipRect(
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      child: SizedBox(
                                        width: inlineVideoController!
                                            .value
                                            .size
                                            .width,
                                        height: inlineVideoController!
                                            .value
                                            .size
                                            .height,
                                        child: VideoPlayer(
                                          inlineVideoController!,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // Controls (Overlay, NICHT gecroppt)
                              if (inlineVideoController != null)
                                Positioned.fill(
                                  child: GestureDetector(
                                    onTap: () {
                                      if (inlineVideoController!
                                          .value
                                          .isPlaying) {
                                        inlineVideoController!.pause();
                                      } else {
                                        inlineVideoController!.play();
                                      }
                                    },
                                    child: Container(
                                      color: Colors.transparent,
                                      child: Stack(
                                        children: [
                                          // Play/Pause Icon in der Mitte (50% kleiner)
                                          Center(
                                            child: ValueListenableBuilder(
                                              valueListenable:
                                                  inlineVideoController!,
                                              builder:
                                                  (
                                                    context,
                                                    VideoPlayerValue value,
                                                    child,
                                                  ) {
                                                    return MouseRegion(
                                                      cursor: SystemMouseCursors
                                                          .click,
                                                      child: Container(
                                                        width: 24,
                                                        height: 24,
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Colors
                                                                  .black54,
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Icon(
                                                          value.isPlaying
                                                              ? Icons.pause
                                                              : Icons
                                                                    .play_arrow,
                                                          color: Colors.white,
                                                          size: 16,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                            ),
                                          ),
                                          // Zeitanzeige unten rechts (läuft hoch)
                                          Positioned(
                                            right: 8,
                                            bottom: 8,
                                            child: ValueListenableBuilder(
                                              valueListenable:
                                                  inlineVideoController!,
                                              builder:
                                                  (
                                                    context,
                                                    VideoPlayerValue value,
                                                    child,
                                                  ) {
                                                    return Container(
                                                      width: 50,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black54,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          _formatDuration(
                                                            value.position,
                                                          ),
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 11,
                                                            fontFeatures: [
                                                              FontFeature.tabularFigures(),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (inlineVideoController == null)
                                Positioned.fill(
                                  child: Builder(
                                    builder: (context) {
                                      final hero = getHeroVideoUrl();
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          if ((hero ?? '').isNotEmpty) {
                                            playNetworkInline(hero!);
                                          }
                                        },
                                        child: (hero == null)
                                            ? Container(
                                                color: Colors.black26,
                                                child: const Icon(
                                                  Icons.play_arrow,
                                                  color: Colors.white54,
                                                  size: 48,
                                                ),
                                              )
                                            : AspectRatio(
                                                aspectRatio: 9 / 16,
                                                child: kIsWeb
                                                    ? _buildWebThumbnail(hero)
                                                    : FutureBuilder<
                                                        Uint8List?>(
                                                        future:
                                                            thumbnailForRemote(
                                                          hero,
                                                        ),
                                                        builder: (
                                                          context,
                                                          snapshot,
                                                        ) {
                                                          if (snapshot.hasData &&
                                                              snapshot.data !=
                                                                  null) {
                                                            return Image.memory(
                                                              snapshot.data!,
                                                              fit: BoxFit.cover,
                                                            );
                                                          }
                                                          return Container(
                                                            color:
                                                                Colors.black26,
                                                            child: const Icon(
                                                              Icons
                                                                  .play_circle_outline,
                                                              color: Colors
                                                                  .white70,
                                                              size: 64,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                              ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: spacing),
                // Galerie (max. 15) - EXAKT wie bei Images
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: totalH,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: remoteFour.length.clamp(0, 15),
                            itemBuilder: (context, index) {
                              final url = remoteFour[index];

                              // Dynamische Größe EXAKT wie bei Images
                              const double nameHeight = 30.0;
                              final double tileImageHeight = leftH - nameHeight;
                              final double tileWidth =
                                  tileImageHeight * (9 / 16);

                              // Original-Dateiname anzeigen (Fallback: URL‑Name)
                              String videoName = fileNameFromUrl(url);
                              if (videoName.length > 28) {
                                videoName = '${videoName.substring(0, 25)}...';
                              }

                              return Container(
                                width: tileWidth,
                                height: leftH,
                                margin: EdgeInsets.only(
                                  right: index < remoteFour.length - 1
                                      ? gridSpacing
                                      : 0,
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: _buildVideoTile(
                                        context,
                                        url,
                                        tileWidth,
                                        tileImageHeight,
                                      ),
                                    ),
                                    SizedBox(
                                      height: nameHeight,
                                      child: Center(
                                        child: Text(
                                          videoName,
                                          style: const TextStyle(fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (isDeleteMode &&
                          (selectedRemoteVideos.length +
                                  selectedLocalVideos.length) >
                              0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: onDeleteModeCancel,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Icon(Icons.close, size: 20),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: onDeleteConfirm,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Icon(Icons.delete, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Video Tile mit Thumbnail, Audio Toggle, Star (Hero), Trash Icon
  Widget _buildVideoTile(BuildContext context, String url, double w, double h) {
    final heroUrl = getHeroVideoUrl();
    final isHero = heroUrl != null && url == heroUrl;
    final audioOn = isHero
        ? false
        : (videoAudioEnabled[url] ?? false); // Hero = IMMER OFF

    return Stack(
      children: [
        Positioned.fill(
          child: _buildVideoThumbNetwork(context, url, isHero: isHero),
        ),
        // Hero-Video-Overlay (star)
        if (isHero)
          const Positioned(
            top: 4,
            left: 6,
            child: SizedBox(
              height: 30,
              width: 30,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '⭐',
                  style: TextStyle(fontSize: 14, color: Color(0xFFFFD700)),
                ),
              ),
            ),
          ),
        // Audio ON/OFF Toggle (oben rechts)
        Positioned(
          top: 4,
          right: 6,
          child: MouseRegion(
            cursor: isHero
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: isHero ? null : () => toggleVideoAudio(url),
              child: Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.transparent),
                child: audioOn
                    ? ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) =>
                            const LinearGradient(
                              colors: [AppColors.magenta, AppColors.lightBlue],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ).createShader(
                              Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                            ),
                        child: const Icon(
                          Icons.volume_up,
                          color: Colors.white,
                          size: 28,
                        ),
                      )
                    : const Icon(
                        Icons.volume_off,
                        color: Colors.white,
                        size: 28,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Video Thumbnail mit Play/Hero/Trash Logik
  Widget _buildVideoThumbNetwork(
    BuildContext context,
    String url, {
    required bool isHero,
  }) {
    final selected = selectedRemoteVideos.contains(url);

    // Hero-Video bekommt GMBC Gradient Border
    if (isHero) {
      return AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFE91E63),
                AppColors.lightBlue,
                Color(0xFF00E5FF),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.black.withValues(alpha: 0.4),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Hero-Thumbnail als statisches Bild
                // Web: nutze Backend-ThumbUrl (Image.network),
                // native: weiterhin lokales Video-Thumbnail (Image.memory)
                if (kIsWeb)
                  _buildWebThumbnail(url)
                else
                  FutureBuilder<Uint8List?>(
                    future: thumbnailForRemote(url),
                    builder: (context, snapshot) {
                      if (snapshot.hasData &&
                          snapshot.data != null &&
                          snapshot.data!.isNotEmpty) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                        );
                      }
                      return Container(color: Colors.black26);
                    },
                  ),
                // Trash Icon (unten rechts)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => onTrashIconTap(url),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? null : const Color(0x30000000),
                          gradient: selected
                              ? Theme.of(
                                  context,
                                ).extension<AppGradients>()!.magentaBlue
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppColors.lightBlue.withValues(alpha: 0.7)
                                : const Color(0x66FFFFFF),
                          ),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                // Trim Icon (unten links) - NUR für Hero-Video in Galerie
                if (onTrimVideo != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => onTrimVideo!(url),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0x30000000),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x66FFFFFF)),
                          ),
                          child: const Icon(
                            Icons.content_cut,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Normale Videos OHNE GMBC Border
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail: Web nutzt Backend-ThumbUrl (Image.network),
            // native Plattformen weiterhin lokales Video-Thumbnail (Image.memory)
            if (kIsWeb)
              _buildWebThumbnail(url)
            else
              FutureBuilder<Uint8List?>(
                future: thumbnailForRemote(url),
                builder: (context, snapshot) {
                  if (snapshot.hasData &&
                      snapshot.data != null &&
                      snapshot.data!.isNotEmpty) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                    );
                  }
                  return Container(color: Colors.black26);
                },
              ),
            // Tap: setzt Hero-Video (nur wenn nicht bereits Hero)
            if (!isHero)
              Positioned.fill(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: () => setHeroVideo(url)),
                  ),
                ),
              ),
            // Trash Icon (unten rechts) mit Cursor Pointer
            Positioned(
              right: 6,
              bottom: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onTrashIconTap(url),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? null : const Color(0x30000000),
                      gradient: selected
                          ? Theme.of(
                              context,
                            ).extension<AppGradients>()!.magentaBlue
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppColors.lightBlue.withValues(alpha: 0.7)
                            : const Color(0x66FFFFFF),
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format Duration für Video-Timer (mm:ss)
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Widget _buildWebThumbnail(String url) {
    final thumbUrl = thumbUrlForMedia?.call(url);

    // 1) Bevorzugt: JPEG-Thumb aus Storage/Media-Docs
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      return Image.network(
        thumbUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
              color: AppColors.lightBlue,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.black26,
            child: const Icon(
              Icons.play_circle_outline,
              color: Colors.white70,
              size: 64,
            ),
          );
        },
      );
    }

    // 2) Fallback: Video-Frame wie im Delete-Dialog via VideoPlayerController.
    // Durch den Cache in _videoControllerForThumb (Key ohne Query) wird der
    // Controller nur einmal pro Video erzeugt → kein Dauernachladen.
    return FutureBuilder<VideoPlayerController?>(
      future: videoControllerForThumb(url),
      builder: (context, snapshot) {
        final ctrl = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting || ctrl == null) {
          return Container(
            color: Colors.black26,
            child: const Icon(
              Icons.play_circle_outline,
              color: Colors.white70,
              size: 64,
            ),
          );
        }
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        );
      },
    );
  }
}
