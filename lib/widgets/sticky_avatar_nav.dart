import 'package:flutter/material.dart';
import 'avatar_nav_bar.dart';

/// Sticky Navigation mit dynamischem Hintergrund
/// Transparent → Schwarz (nach 150px)
class StickyAvatarNav extends StatefulWidget {
  final String avatarId;
  final String currentScreen;
  final Widget child; // Der scrollbare Content

  const StickyAvatarNav({
    super.key,
    required this.avatarId,
    required this.currentScreen,
    required this.child,
  });

  @override
  State<StickyAvatarNav> createState() => _StickyAvatarNavState();
}

class _StickyAvatarNavState extends State<StickyAvatarNav> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Berechne Opacity: 0.0 bei 0px → 1.0 bei 150px
    final opacity = (_scrollOffset / 150.0).clamp(0.0, 1.0);

    return Column(
      children: [
        // Sticky Navigation Bar mit dynamischem Hintergrund
        Container(
          color: Colors.black.withValues(alpha: opacity),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: AvatarNavBar(
            avatarId: widget.avatarId,
            currentScreen: widget.currentScreen,
          ),
        ),
        // Scrollable Content
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                setState(() {
                  _scrollOffset = _scrollController.offset;
                });
              }
              return false;
            },
            child: widget.child is SingleChildScrollView
                ? widget.child
                : SingleChildScrollView(
                    controller: _scrollController,
                    child: widget.child,
                  ),
          ),
        ),
      ],
    );
  }
}
