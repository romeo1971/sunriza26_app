import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import '../../models/media_models.dart';
import '../../theme/app_theme.dart';
import '../../services/audio_cover_service.dart';

/// Audio Cover Images Overlay - zeigt 5 Platzhalter für Cover Images
/// Click auf Platzhalter → Upload + Crop (9:16 oder 16:9)
/// Click auf vorhandenes Image → Delete/Update
class AudioCoverImagesOverlay extends StatefulWidget {
  final AvatarMedia audioMedia;
  final Function(List<AudioCoverImage>) onImagesChanged;

  const AudioCoverImagesOverlay({
    super.key,
    required this.audioMedia,
    required this.onImagesChanged,
  });

  @override
  State<AudioCoverImagesOverlay> createState() => _AudioCoverImagesOverlayState();
}

class _AudioCoverImagesOverlayState extends State<AudioCoverImagesOverlay> {
  late List<AudioCoverImage?> _coverImages;
  final _picker = ImagePicker();
  final _coverService = AudioCoverService();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Initialisiere mit vorhandenen Cover Images (max 5 Platzhalter)
    _coverImages = List.filled(5, null);
    if (widget.audioMedia.coverImages != null) {
      for (var img in widget.audioMedia.coverImages!) {
        if (img.index >= 0 && img.index < 5) {
          _coverImages[img.index] = img;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coverCount = _coverImages.where((e) => e != null).length;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(coverCount),
            
            // Grid mit 5 Platzhaltern
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _buildCoverGrid(),
              ),
            ),
            
            // Footer Buttons
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int coverCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          
          // Titel
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Audio Cover Images',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$coverCount / 5 Cover',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Close Button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: 5,
      itemBuilder: (context, index) => _buildCoverPlaceholder(index),
    );
  }

  Widget _buildCoverPlaceholder(int index) {
    final coverImage = _coverImages[index];
    final isEmpty = coverImage == null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => isEmpty ? _addCoverImage(index) : _showImageOptions(index),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEmpty
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppColors.magenta.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: isEmpty
              ? _buildEmptyPlaceholder(index)
              : _buildCoverPreview(coverImage),
        ),
      ),
    );
  }

  Widget _buildEmptyPlaceholder(int index) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          color: Colors.white.withValues(alpha: 0.4),
          size: 48,
        ),
        const SizedBox(height: 8),
        Text(
          'Cover ${index + 1}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Hinzufügen',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildCoverPreview(AudioCoverImage coverImage) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover Image Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            coverImage.thumbUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              color: Colors.grey.shade800,
              child: const Icon(Icons.broken_image, color: Colors.white54),
            ),
          ),
        ),
        
        // Aspect Ratio Badge
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              coverImage.aspectRatio > 1 ? '16:9' : '9:16',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
        // Index Badge
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${coverImage.index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Info Text
          Expanded(
            child: Text(
              'Tipp: Mindestens 1 Cover empfohlen. Bilder rotieren im Chat.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ),
          
          // Close Button
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
  }

  /// Add Cover Image: Image Picker → Crop → Upload
  Future<void> _addCoverImage(int index) async {
    if (_isUploading) return;

    try {
      // 1. Image Picker (Galerie)
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final bytes = await image.readAsBytes();

      // 2. Crop Dialog öffnen
      await _openCropDialog(bytes, index);
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Auswählen: $e')),
        );
      }
    }
  }

  /// Crop Dialog (9:16 oder 16:9)
  Future<void> _openCropDialog(Uint8List imageBytes, int index) async {
    double currentAspect = 9 / 16; // Default: Portrait
    final cropController = cyi.CropController();
    bool isCropping = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.magenta, width: 3),
            ),
            content: SizedBox(
              width: 480,
              height: 560,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Row(
                      children: [
                        const Text(
                          'Cover Zuschneiden',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        // Aspect Ratio Buttons
                        _buildAspectButton(
                          '9:16',
                          9 / 16,
                          currentAspect,
                          () {
                            setLocal(() => currentAspect = 9 / 16);
                            cropController.aspectRatio = 9 / 16;
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildAspectButton(
                          '16:9',
                          16 / 9,
                          currentAspect,
                          () {
                            setLocal(() => currentAspect = 16 / 9);
                            cropController.aspectRatio = 16 / 9;
                          },
                        ),
                      ],
                    ),
                  ),
                  // Crop Area
                  Expanded(
                    child: cyi.Crop(
                      image: imageBytes,
                      controller: cropController,
                      aspectRatio: currentAspect,
                      withCircleUi: false,
                      baseColor: Colors.black,
                      maskColor: Colors.black.withValues(alpha: 0.7),
                      cornerDotBuilder: (size, edgeAlignment) => Container(
                        width: size,
                        height: size,
                        decoration: const BoxDecoration(
                          color: AppColors.lightBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      onCropped: (result) async {
                        if (!isCropping) return;
                        if (result is cyi.CropSuccess) {
                          Navigator.pop(ctx);
                          await _uploadCoverImage(result.croppedImage, index, currentAspect);
                        }
                      },
                    ),
                  ),
                  // Footer Buttons
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isCropping ? null : () => Navigator.pop(ctx),
                          child: const Text('Abbrechen'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isCropping
                              ? null
                              : () {
                                  setLocal(() => isCropping = true);
                                  cropController.crop();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.magenta,
                          ),
                          child: isCropping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Hochladen'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAspectButton(
    String label,
    double aspect,
    double currentAspect,
    VoidCallback onTap,
  ) {
    final isActive = (aspect - currentAspect).abs() < 0.01;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [AppColors.magenta, AppColors.lightBlue],
                )
              : null,
          color: isActive ? null : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Upload Cover Image mit AudioCoverService
  Future<void> _uploadCoverImage(
    Uint8List croppedBytes,
    int index,
    double aspectRatio,
  ) async {
    setState(() => _isUploading = true);

    try {
      // Extract avatarId from audioMedia
      final avatarId = widget.audioMedia.avatarId;
      final audioId = widget.audioMedia.id;

      // Upload mit Service
      final coverImage = await _coverService.uploadCoverImage(
        avatarId: avatarId,
        audioId: audioId,
        imageBytes: croppedBytes,
        index: index,
        aspectRatio: aspectRatio,
      );

      // Update local state
      setState(() {
        _coverImages[index] = coverImage;
      });

      // Update Firestore
      final updatedImages = _coverImages.whereType<AudioCoverImage>().toList();
      await _coverService.updateAudioCoverImages(
        avatarId: avatarId,
        audioId: audioId,
        coverImages: updatedImages,
      );

      // Callback
      widget.onImagesChanged(updatedImages);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover Image hochgeladen!')),
        );
      }
    } catch (e) {
      debugPrint('Error uploading cover: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Upload: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// Delete / Update Dialog
  Future<void> _showImageOptions(int index) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cover ${index + 1}'),
        content: const Text('Was möchten Sie tun?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteCoverImage(index);
            },
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addCoverImage(index); // Replace = Delete + Add
            },
            child: const Text('Ersetzen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  /// Delete Cover Image
  Future<void> _deleteCoverImage(int index) async {
    setState(() => _isUploading = true);

    try {
      final avatarId = widget.audioMedia.avatarId;
      final audioId = widget.audioMedia.id;

      // Delete from Storage + Firestore
      await _coverService.removeCoverImage(
        avatarId: avatarId,
        audioId: audioId,
        audioMedia: widget.audioMedia,
        index: index,
      );

      // Update local state
      setState(() {
        _coverImages[index] = null;
      });

      // Callback
      final updatedImages = _coverImages.whereType<AudioCoverImage>().toList();
      widget.onImagesChanged(updatedImages);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover Image gelöscht!')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting cover: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}

