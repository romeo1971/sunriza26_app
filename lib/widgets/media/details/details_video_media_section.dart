import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../theme/app_theme.dart';
import '../../video_player_widget.dart';

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
  final VoidCallback onDeleteModeCancel;
  final VoidCallback onDeleteConfirm;
  final ValueChanged<String> onTrashIconTap; // (url) => { setState... }

  // Video Controller Helper
  final Future<VideoPlayerController?> Function(String url)
  videoControllerForThumb;

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
  });

  @override
  Widget build(BuildContext context) {
    final List<String> remoteFour = videoUrls.take(15).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          const double spacing = 16.0;
          const double minThumbWidth = 120.0;
          const double gridSpacing = 12.0;
          const double navBtnH = 40.0;
          final double minNavWidth = (navBtnH * 3) + (8 * 2);
          final double minRightWidth = (2 * minThumbWidth) + gridSpacing;
          double leftW = cons.maxWidth - spacing - minRightWidth;
          if (leftW > 148) leftW = 148;
          if (leftW < minNavWidth) {
            leftW = minNavWidth;
          }
          final double leftH = leftW * (16 / 9);
          final double totalH = leftH;
          final double rowWidth = leftW + spacing + leftW;

          return SizedBox(
            width: rowWidth,
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
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            if (inlineVideoController != null)
                              Positioned.fill(
                                child: VideoPlayerWidget(
                                  controller: inlineVideoController!,
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
                                              child: FutureBuilder<Uint8List?>(
                                                future: thumbnailForRemote(
                                                  hero,
                                                ),
                                                builder: (context, snapshot) {
                                                  if (snapshot.hasData &&
                                                      snapshot.data != null) {
                                                    return Image.memory(
                                                      snapshot.data!,
                                                      fit: BoxFit.cover,
                                                    );
                                                  }
                                                  return Container(
                                                    color: Colors.black26,
                                                    child: const Icon(
                                                      Icons.play_circle_outline,
                                                      color: Colors.white70,
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
                  ],
                ),
                const SizedBox(width: spacing),
                // Galerie (max. 15)
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: leftH,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: remoteFour.length.clamp(0, 15),
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: gridSpacing),
                            itemBuilder: (context, index) {
                              final url = remoteFour[index];
                              final thumbH = leftH;
                              final thumbW = thumbH / 16 * 9;
                              return SizedBox(
                                width: thumbW,
                                height: thumbH,
                                child: _buildVideoTile(
                                  context,
                                  url,
                                  thumbW,
                                  thumbH,
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
            FutureBuilder<VideoPlayerController?>(
              future: videoControllerForThumb(url),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData &&
                    snapshot.data != null) {
                  final controller = snapshot.data!;
                  if (controller.value.isInitialized) {
                    return FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.size.width,
                        height: controller.value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    );
                  }
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
}
