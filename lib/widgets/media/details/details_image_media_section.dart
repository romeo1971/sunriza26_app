import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../services/localization_service.dart';

/// Image Media Section für Details Screen
///
/// Vollständig extrahierte, modulare Widget-Sektion für den Image-Bereich.
/// Unterstützt List-View (Timeline) und Grid-View (Kacheln).
///
/// Verwendung:
/// ```dart
/// DetailsImageMediaSection(
///   // View Mode
///   heroViewMode: _heroViewMode,
///   isListViewExpanded: _isListViewExpanded,
///
///   // Images
///   imageUrls: _imageUrls,
///   profileImageUrl: _profileImageUrl,
///   profileLocalPath: _profileLocalPath,
///
///   // Timeline State
///   imageActive: _imageActive,
///   imageDurations: _imageDurations,
///   imageExplorerVisible: _imageExplorerVisible,
///   isImageLoopMode: _isImageLoopMode,
///   isTimelineEnabled: _isTimelineEnabled,
///
///   // Delete Mode
///   isDeleteMode: _isDeleteMode,
///   selectedRemoteImages: _selectedRemoteImages,
///   selectedLocalImages: _selectedLocalImages,
///   isGeneratingAvatar: _isGeneratingAvatar,
///   avatarData: _avatarData,
///
///   // Callbacks
///   onExpansionChanged: (expanded) => setState(() => _isListViewExpanded = expanded),
///   onLoopModeToggle: () { setState(() => _isImageLoopMode = !_isImageLoopMode); _saveTimelineData(); },
///   onTimelineEnabledToggle: () { setState(() => _isTimelineEnabled = !_isTimelineEnabled); _saveTimelineData(); },
///   onReorder: (oldIdx, newIdx) async { ... },
///   onImageActiveTap: (url) { setState(() => _imageActive[url] = !_imageActive[url]); _saveTimelineData(); },
///   onExplorerVisibleTap: (url) async { await _showExplorerInfoDialog(); setState(() => _imageExplorerVisible[url] = !_imageExplorerVisible[url]); await _saveTimelineData(); },
///   onDurationChanged: (url, minutes) { setState(() => _imageDurations[url] = minutes * 60); _saveTimelineData(); },
///   onDeleteModeCancel: () { setState(() { _isDeleteMode = false; _selectedRemoteImages.clear(); _selectedLocalImages.clear(); }); },
///   onDeleteConfirm: _confirmDeleteSelectedImages,
///   onGenerateAvatar: _handleGenerateAvatar,
///
///   // Helper functions
///   fileNameFromUrl: _fileNameFromUrl,
///   getTotalEndTime: _getTotalEndTime,
///   getImageStartTime: _getImageStartTime,
///   handleImageError: _handleImageError,
///   buildHeroImageThumbNetwork: _buildHeroImageThumbNetwork,
/// )
/// ```
class DetailsImageMediaSection extends StatelessWidget {
  // View Mode
  final String heroViewMode; // 'list' oder 'grid'
  final bool isListViewExpanded;

  // Images
  final List<String> imageUrls;
  final String? profileImageUrl;
  final String? profileLocalPath;

  // Timeline State (Maps: URL -> Value)
  final Map<String, bool> imageActive;
  final Map<String, int> imageDurations; // in Sekunden
  final Map<String, bool> imageExplorerVisible;
  final bool isImageLoopMode;
  final bool isTimelineEnabled;

  // Delete Mode
  final bool isDeleteMode;
  final Set<String> selectedRemoteImages;
  final Set<String> selectedLocalImages;
  final bool isGeneratingAvatar;
  final dynamic avatarData; // Typ aus der App
  final Map<String, bool> isRecropping; // URL -> Loading Spinner anzeigen

  // Callbacks
  final ValueChanged<bool> onExpansionChanged;
  final VoidCallback onLoopModeToggle;
  final VoidCallback onTimelineEnabledToggle;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onImageActiveTap;
  final ValueChanged<String> onExplorerVisibleTap;
  final void Function(String url, int minutes) onDurationChanged;
  final VoidCallback onDeleteModeCancel;
  final VoidCallback onDeleteConfirm;
  final Future<void> Function() onGenerateAvatar;
  final ValueChanged<String> onSetHeroImage;
  final ValueChanged<String> onCropImage;

  // Helper functions
  final String Function(String url) fileNameFromUrl;
  final String Function() getTotalEndTime;
  final String Function(int index) getImageStartTime;
  final void Function(String url) handleImageError;
  final Widget Function(String url, bool isHero) buildHeroImageThumbNetwork;

  const DetailsImageMediaSection({
    super.key,
    required this.heroViewMode,
    required this.isListViewExpanded,
    required this.imageUrls,
    required this.profileImageUrl,
    required this.profileLocalPath,
    required this.imageActive,
    required this.imageDurations,
    required this.imageExplorerVisible,
    required this.isImageLoopMode,
    required this.isTimelineEnabled,
    required this.isDeleteMode,
    required this.selectedRemoteImages,
    required this.selectedLocalImages,
    required this.isGeneratingAvatar,
    required this.avatarData,
    required this.isRecropping,
    required this.onExpansionChanged,
    required this.onLoopModeToggle,
    required this.onTimelineEnabledToggle,
    required this.onReorder,
    required this.onImageActiveTap,
    required this.onExplorerVisibleTap,
    required this.onDurationChanged,
    required this.onDeleteModeCancel,
    required this.onDeleteConfirm,
    required this.onGenerateAvatar,
    required this.onSetHeroImage,
    required this.onCropImage,
    required this.fileNameFromUrl,
    required this.getTotalEndTime,
    required this.getImageStartTime,
    required this.handleImageError,
    required this.buildHeroImageThumbNetwork,
  });

  @override
  Widget build(BuildContext context) {
    // Verwende unterschiedliche Layouts je nach View-Mode
    if (heroViewMode == 'list') {
      return _buildHeroImagesListView(context);
    } else {
      return _buildHeroImagesGridView(context);
    }
  }

  // Listen-View: Drag & Drop sortierbare Liste
  Widget _buildHeroImagesListView(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        const double listItemHeight = 80.0;

        // Berechne volle verfügbare Höhe wenn expanded
        final double screenHeight = MediaQuery.of(ctx).size.height;
        final double appBarHeight = 56.0;
        final double heroNavHeight = 35.0;
        final double footerHeight = 64.0;
        final double paddingBottom = 24.0;
        final double infoTextHeight = 40.0;

        final double availableHeight =
            screenHeight -
            appBarHeight -
            heroNavHeight -
            footerHeight -
            paddingBottom -
            infoTextHeight -
            16.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.white24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ExpansionTile(
                  initiallyExpanded: isListViewExpanded,
                  onExpansionChanged: onExpansionChanged,
                  collapsedBackgroundColor: Colors.white.withValues(
                    alpha: 0.04,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  collapsedIconColor: AppColors.magenta,
                  iconColor: AppColors.lightBlue,
                  title: Row(
                    children: [
                      const Text(
                        'Timeline',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Loop/Ende Teil
                            InkWell(
                              onTap: onLoopModeToggle,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: isImageLoopMode
                                      ? Theme.of(
                                          context,
                                        ).extension<AppGradients>()!.magentaBlue
                                      : null,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    bottomLeft: Radius.circular(4),
                                  ),
                                ),
                                child: SizedBox(
                                  width: 30,
                                  child: Center(
                                    child: Text(
                                      isImageLoopMode ? 'Loop' : 'Ende',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Pipe
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text(
                                '|',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                            // ON/OFF Teil
                            InkWell(
                              onTap: onTimelineEnabledToggle,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: isTimelineEnabled
                                      ? Theme.of(
                                          context,
                                        ).extension<AppGradients>()!.magentaBlue
                                      : null,
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(4),
                                    bottomRight: Radius.circular(4),
                                  ),
                                ),
                                child: SizedBox(
                                  width: 24,
                                  child: Center(
                                    child: Text(
                                      isTimelineEnabled ? 'ON' : 'OFF',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  children: [
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: availableHeight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            itemCount: imageUrls.length,
                            onReorder: onReorder,
                            itemBuilder: (context, index) {
                              final url = imageUrls[index];
                              final isHero =
                                  profileImageUrl == url ||
                                  (profileImageUrl == null && index == 0);
                              final imageName = fileNameFromUrl(url);
                              final isActive = imageActive[url] ?? true;

                              return Stack(
                                key: ValueKey(url),
                                children: [
                                  Container(
                                    height: listItemHeight,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      gradient: isHero
                                          ? const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFFE91E63),
                                                AppColors.lightBlue,
                                                Color(0xFF00E5FF),
                                              ],
                                            )
                                          : (!isHero && isActive
                                                ? const LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Color(0x4D004D00),
                                                      Color(0x26008000),
                                                    ],
                                                  )
                                                : null),
                                      color: isHero
                                          ? null
                                          : (!isHero && isActive
                                                ? null
                                                : Colors.white.withValues(
                                                    alpha: 0.05,
                                                  )),
                                    ),
                                    child: Row(
                                      children: [
                                        // Thumbnail (Click = Timeline Active/Inactive)
                                        MouseRegion(
                                          cursor: isHero
                                              ? SystemMouseCursors.basic
                                              : SystemMouseCursors.click,
                                          child: GestureDetector(
                                            onTap: isHero
                                                ? null
                                                : () => onImageActiveTap(url),
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.horizontal(
                                                    left: Radius.circular(8),
                                                    right: Radius.zero,
                                                  ),
                                              child: SizedBox(
                                                width: listItemHeight * 9 / 16,
                                                height: listItemHeight,
                                                child: Image.network(
                                                  url,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // 3 Reihen: Zeit, Dropdowns, Name
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Reihe 1: Zeit + Auge-Icon
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      isHero
                                                          ? '00:00 - ${getTotalEndTime()}'
                                                          : getImageStartTime(
                                                              index,
                                                            ),
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                  if (!isHero)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 8,
                                                          ),
                                                      child: InkWell(
                                                        onTap: () =>
                                                            onExplorerVisibleTap(
                                                              url,
                                                            ),
                                                        child:
                                                            (imageExplorerVisible[url] ??
                                                                false)
                                                            ? ShaderMask(
                                                                shaderCallback: (bounds) =>
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .extension<
                                                                          AppGradients
                                                                        >()!
                                                                        .magentaBlue
                                                                        .createShader(
                                                                          bounds,
                                                                        ),
                                                                child: const Icon(
                                                                  Icons
                                                                      .visibility,
                                                                  size: 20,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              )
                                                            : const Icon(
                                                                Icons
                                                                    .visibility_off,
                                                                size: 20,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              // Reihe 2: Dropdown (nur Minuten 1-30)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: DropdownButton<int>(
                                                  value:
                                                      (((imageDurations[url] ??
                                                                  60) ~/
                                                              60))
                                                          .clamp(1, 30),
                                                  isDense: true,
                                                  underline:
                                                      const SizedBox.shrink(),
                                                  dropdownColor: Colors.black87,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                  ),
                                                  items:
                                                      List.generate(
                                                            30,
                                                            (i) => i + 1,
                                                          )
                                                          .map(
                                                            (min) =>
                                                                DropdownMenuItem(
                                                                  value: min,
                                                                  child: Text(
                                                                    '$min Min.',
                                                                  ),
                                                                ),
                                                          )
                                                          .toList(),
                                                  onChanged: (newMin) {
                                                    if (newMin != null) {
                                                      onDurationChanged(
                                                        url,
                                                        newMin,
                                                      );
                                                    }
                                                  },
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              // Reihe 3: Name oder Loading Spinner
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child:
                                                        (isRecropping[url] ==
                                                            true)
                                                        ? Row(
                                                            children: [
                                                              SizedBox(
                                                                width: 12,
                                                                height: 12,
                                                                child: CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                  color: Colors
                                                                      .white70,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Text(
                                                                'Cropping...',
                                                                style: TextStyle(
                                                                  color: Colors
                                                                      .white70,
                                                                  fontSize: 12,
                                                                  fontStyle:
                                                                      FontStyle
                                                                          .italic,
                                                                ),
                                                              ),
                                                            ],
                                                          )
                                                        : Text(
                                                            imageName,
                                                            style: TextStyle(
                                                              color: isHero
                                                                  ? Colors.white
                                                                  : (imageActive[url] ??
                                                                        true)
                                                                  ? Colors.white
                                                                  : Colors.grey,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Drag Handle rechts
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                              child: Icon(
                                                Icons.drag_indicator,
                                                color: Colors.white70,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Grid-View: Kacheln mit Hero Image links
  Widget _buildHeroImagesGridView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          const double spacing = 16.0;
          const double gridSpacing = 12.0;
          const double navBtnH = 40.0;
          const double leftH = 223.0;
          final double leftW = leftH * (9 / 16);
          const double totalH = leftH;

          return SizedBox(
            width: cons.maxWidth,
            height: totalH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero-Image links GROSS
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
                              Positioned.fill(
                                child: profileLocalPath != null
                                    ? Image.file(
                                        File(profileLocalPath!),
                                        fit: BoxFit.cover,
                                      )
                                    : (profileImageUrl != null
                                          ? Image.network(
                                              profileImageUrl!,
                                              fit: BoxFit.cover,
                                              key: ValueKey(profileImageUrl!),
                                              errorBuilder:
                                                  (context, error, stack) {
                                                    handleImageError(
                                                      profileImageUrl!,
                                                    );
                                                    return Container(
                                                      color: Colors.black26,
                                                      alignment:
                                                          Alignment.center,
                                                      child: const Icon(
                                                        Icons
                                                            .image_not_supported,
                                                        color: Colors.white54,
                                                        size: 48,
                                                      ),
                                                    );
                                                  },
                                            )
                                          : Container(
                                              color: Colors.white12,
                                              child: const Icon(
                                                Icons.person,
                                                color: Colors.white54,
                                                size: 64,
                                              ),
                                            )),
                              ),                              
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
                const SizedBox(width: spacing),
                // Galerie rechts
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
                            itemCount: imageUrls.length,
                            itemBuilder: (context, index) {
                              final url = imageUrls[index];
                              final isHero =
                                  profileImageUrl == url ||
                                  (profileImageUrl == null && index == 0);

                              const nameHeight = 30.0;
                              final tileImageHeight = leftH - nameHeight;
                              final tileWidth = tileImageHeight * (9 / 16);
                              final imageName = fileNameFromUrl(url);
                              final isActive = imageActive[url] ?? true;

                              return Stack(
                                children: [
                                  Container(
                                    width: tileWidth,
                                    height: leftH,
                                    margin: EdgeInsets.only(
                                      right: index < imageUrls.length - 1
                                          ? gridSpacing
                                          : 0,
                                    ),
                                    child: Column(
                                      children: [
                                        MouseRegion(
                                          cursor: isHero
                                              ? SystemMouseCursors.basic
                                              : SystemMouseCursors.click,
                                          child: GestureDetector(
                                            onTap: isHero
                                                ? null
                                                : () => onSetHeroImage(url),
                                            child: SizedBox(
                                              width: tileWidth,
                                              height: tileImageHeight,
                                              child: buildHeroImageThumbNetwork(
                                                url,
                                                isHero,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: nameHeight,
                                          child: Center(
                                            child: (isRecropping[url] == true)
                                                ? Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      SizedBox(
                                                        width: 10,
                                                        height: 10,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 1.5,
                                                              color: Colors
                                                                  .white70,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Cropping...',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 10,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Text(
                                                    imageName,
                                                    style: TextStyle(
                                                      color: isHero
                                                          ? Colors.white
                                                          : (isActive
                                                                ? Colors.white70
                                                                : Colors.grey),
                                                      fontSize: 11,
                                                      fontWeight: isHero
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Status-Punkte oben rechts
                                  if (!isHero)
                                    Positioned(
                                      top: 6,
                                      right:
                                          (index < imageUrls.length - 1
                                              ? gridSpacing
                                              : 0) +
                                          6,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Grüner Punkt = Timeline aktiv
                                          if (isActive)
                                            Container(
                                              width: 13,
                                              height: 13,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1.0,
                                                ),
                                              ),
                                            ),
                                          // Abstand zwischen Punkten
                                          if (isActive &&
                                              (imageExplorerVisible[url] ??
                                                  false))
                                            const SizedBox(width: 6),
                                          // GMBC Punkt = Explorer aktiv
                                          if (imageExplorerVisible[url] ??
                                              false)
                                            Container(
                                              width: 13,
                                              height: 13,
                                              decoration: BoxDecoration(
                                                gradient: Theme.of(context)
                                                    .extension<AppGradients>()!
                                                    .magentaBlue,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1.0,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  // Crop-Icon unten links (nur wenn NICHT Delete-Mode und NICHT Hero)
                                  if (!isDeleteMode && !isHero)
                                    Positioned(
                                      bottom: nameHeight + 6,
                                      left: 6,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () => onCropImage(url),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0x30000000),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0x66FFFFFF),
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.crop,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      // Toolbar für Delete-Mode
                      if (isDeleteMode &&
                          (selectedRemoteImages.length +
                                  selectedLocalImages.length) >
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
}
