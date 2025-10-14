import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import 'details_media_tab_button.dart';

/// Navigationsleiste für Media-Bereich (Images/Videos)
class MediaNavigationBar extends StatelessWidget {
  final String currentTab;
  final String currentViewMode;
  final int imageCount;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onUpload;
  final VoidCallback onInfoPressed;
  final VoidCallback onViewModeToggle;

  const MediaNavigationBar({
    super.key,
    required this.currentTab,
    required this.currentViewMode,
    required this.imageCount,
    required this.onTabChanged,
    required this.onUpload,
    required this.onInfoPressed,
    required this.onViewModeToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Hintergrund: quasi black
        Container(height: 35, color: const Color(0xFF0D0D0D)),
        // Weißes Overlay #ffffff15
        Positioned.fill(child: Container(color: const Color(0x15FFFFFF))),
        // Inhalt
        Container(
          height: 35,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              MediaTabButton(
                tab: 'images',
                icon: Icons.image_outlined,
                currentTab: currentTab,
                onTabChanged: onTabChanged,
              ),
              MediaTabButton(
                tab: 'videos',
                icon: Icons.videocam_outlined,
                currentTab: currentTab,
                onTabChanged: onTabChanged,
              ),
              // Upload-Button
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: MouseRegion(
                  cursor: (currentTab == 'images' && imageCount >= 15)
                      ? SystemMouseCursors.forbidden
                      : SystemMouseCursors.click,
                  child: SizedBox(
                    height: 35,
                    child: TextButton(
                      onPressed: (currentTab == 'images' && imageCount >= 15)
                          ? null
                          : onUpload,
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        minimumSize: const WidgetStatePropertyAll(Size(40, 35)),
                      ),
                      child: Container(
                        height: double.infinity,
                        decoration: BoxDecoration(
                          gradient: Theme.of(
                            context,
                          ).extension<AppGradients>()!.magentaBlue,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: const Icon(
                          Icons.file_upload,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Info-Button für Explorer-Dialog
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  height: 35,
                  width: 35,
                  child: IconButton(
                    onPressed: onInfoPressed,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              // Toggle View-Mode (Kacheln / Liste) - ganz rechts
              SizedBox(
                height: 35,
                width: 35,
                child: TextButton(
                  onPressed: onViewModeToggle,
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    minimumSize: const WidgetStatePropertyAll(Size(35, 35)),
                    backgroundColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    currentViewMode == 'grid'
                        ? Icons.view_list_outlined
                        : Icons.grid_view_outlined,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
