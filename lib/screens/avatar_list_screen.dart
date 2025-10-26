import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/avatar_data.dart' as model;
import '../widgets/app_drawer.dart';
import '../services/avatar_service.dart';
import '../services/localization_service.dart';
// import '../services/fact_review_service.dart';
import 'avatar_review_facts_screen.dart';
import 'package:provider/provider.dart';
import '../widgets/custom_text_field.dart';
import 'package:flutter/services.dart';

class AvatarListScreen extends StatefulWidget {
  const AvatarListScreen({super.key});

  @override
  State<AvatarListScreen> createState() => _AvatarListScreenState();
}

class _AvatarListScreenState extends State<AvatarListScreen>
    with AutomaticKeepAliveClientMixin {
  final AvatarService _avatarService = AvatarService();
  List<model.AvatarData> _avatars = [];
  List<model.AvatarData> _filteredAvatars = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  int _currentPage = 0;
  static const int _avatarsPerPage = 4;

  // Erzeuge kurze, nicht rückrechenbare Code-IDs (FNV-1a 32-bit → Base36)
  String _shortCode(String input) {
    int hash = 0x811C9DC5;
    for (int i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // Base36 kompakt
    return hash.abs().toRadixString(36);
  }

  String _genSessionId() {
    // sehr kurze Session-ID für Iframe (client-seitig; eigentlicher Token-Join via Backend)
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rnd = (DateTime.now().microsecondsSinceEpoch & 0xFFFFFF)
        .toRadixString(36);
    return 'session-$ts$rnd';
  }

  String _buildEmbedUrl(String avatarId, {bool withSession = false}) {
    final code = _shortCode(avatarId);
    final room = withSession ? _genSessionId() : '{ROOM_ID}';
    return 'https://www.hauau.com/app/embed/chat?room=$room&code=$code';
  }

  Widget _buildEmbedBadge(String avatarId) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final url = _buildEmbedUrl(avatarId, withSession: true);
          await Clipboard.setData(ClipboardData(text: url));
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Embed-Link kopiert')));
        },
        child: Container(
          height: 24,
          constraints: const BoxConstraints(minHeight: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE91E63), AppColors.lightBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.link, size: 14, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Embed-Link',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAvatars();
  }

  Future<void> _loadAvatars() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final avatars = await _avatarService.getUserAvatars();
      setState(() {
        _avatars = avatars;
        _isLoading = false;
      });
      if (mounted) _applyFilter(resetPage: true);
    } on FirebaseException catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        final msg = e.code == 'failed-precondition'
            ? loc.t('avatars.errorIndexMissing')
            : (e.message ?? e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('avatars.errorLoad', params: {'msg': msg})),
          ),
        );
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loc.t('avatars.errorLoad', params: {'msg': e.toString()}),
            ),
          ),
        );
      }
    }
  }

  void _applyFilter({bool resetPage = false}) {
    final term = _searchTerm.trim().toLowerCase();
    if (resetPage) _currentPage = 0;
    List<model.AvatarData> filtered;
    if (term.isEmpty) {
      filtered = List.from(_avatars);
    } else {
      filtered = _avatars.where((avatar) {
        final searchable = [
          avatar.firstName,
          avatar.nickname ?? '',
          avatar.lastName ?? '',
          avatar.city ?? '',
          avatar.postalCode ?? '',
          avatar.country ?? '',
        ].join(' ').toLowerCase();
        return searchable.contains(term);
      }).toList();
    }
    setState(() {
      _filteredAvatars = filtered;
      if (_currentPage >= totalPages && totalPages > 0) {
        _currentPage = totalPages - 1;
      }
    });
  }

  int get totalPages {
    if (_filteredAvatars.isEmpty) return 1;
    return (_filteredAvatars.length / _avatarsPerPage).ceil().clamp(1, 1000000);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // WICHTIG für AutomaticKeepAliveClientMixin
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(loc.t('avatars.title')),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder: (context) => IconButton(
            style: IconButton.styleFrom(
              overlayColor: Colors.white.withValues(alpha: 0.1),
            ),
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          // Refresh Icon mit GMBC Gradient
          IconButton(
            onPressed: _loadAvatars,
            style: IconButton.styleFrom(
              overlayColor: Colors.white.withValues(alpha: 0.1),
            ),
            icon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFFE91E63),
                  AppColors.lightBlue,
                  Color(0xFF00E5FF),
                ],
              ).createShader(bounds),
              child: const Icon(Icons.refresh, color: Colors.white),
            ),
            tooltip: loc.t('avatars.refreshTooltip'),
          ),
          // Add Icon mit GMBC Gradient
          if (!_isLoading && _avatars.isNotEmpty)
            IconButton(
              onPressed: _createNewAvatar,
              style: IconButton.styleFrom(
                overlayColor: Colors.white.withValues(alpha: 0.1),
              ),
              icon: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFFE91E63),
                    AppColors.lightBlue,
                    Color(0xFF00E5FF),
                  ],
                ).createShader(bounds),
                child: const Icon(Icons.add, color: Colors.white),
              ),
              tooltip: loc.t('avatars.createTooltip'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAvatars,
              child: _avatars.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [_buildEmptyState()],
                    )
                  : _buildAvatarList(),
            ),
      // Kein zusätzliches FAB: im Empty-State führt der zentrale Button,
      // bei bestehenden Avataren reicht das Plus-Symbol in der AppBar.
      floatingActionButton: null,
    );
  }

  Widget _buildEmptyState() {
    final loc = context.watch<LocalizationService>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _createNewAvatar,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
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
                  child: const Icon(
                    Icons.person_add,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              loc.t('avatars.emptyTitle'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              loc.t('avatars.emptySubtitle'),
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarList() {
    final int total = _filteredAvatars.length;
    final int start = _currentPage * _avatarsPerPage;
    final int end = (start + _avatarsPerPage).clamp(0, total);
    final List<model.AvatarData> pageItems = total == 0
        ? []
        : _filteredAvatars.sublist(start, end);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSearchField(),
              const SizedBox(height: 12),
              if (pageItems.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  alignment: Alignment.center,
                  child: Text(
                    context.read<LocalizationService>().t(
                      'avatars.noSearchResults',
                    ),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                  ),
                )
              else
                ...pageItems.map(_buildAvatarCard),
              const SizedBox(height: 12),
            ],
          ),
        ),
        // Pagination fixed am Ende
        Container(
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.95),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: _buildPagination(total),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    final loc = context.watch<LocalizationService>();
    return CustomTextField(
      label: loc.t('avatars.searchHint'),
      controller: _searchController,
      prefixIcon: const Icon(Icons.search, color: Colors.white70),
      suffixIcon: _searchTerm.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _searchTerm = '';
                _applyFilter(resetPage: true);
              },
            )
          : null,
      onChanged: (value) {
        _searchTerm = value;
        _applyFilter(resetPage: true);
      },
    );
  }

  Widget _buildPagination(int total) {
    if (total <= _avatarsPerPage) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
              color: Colors.white70,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
          ),
          Text(
            '${_currentPage + 1} / $totalPages',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
              color: Colors.white70,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarCard(model.AvatarData avatar) {
    final loc = context.watch<LocalizationService>();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar-Bild 9:16 (ca. 2.5x höher) - MIT Chat-Klick
                    Builder(
                      builder: (context) {
                        const double h = 150; // ~2.5 * 60
                        const double w = h * 9 / 16;
                        return InkWell(
                          onTap: () => _openAvatarChat(avatar),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: w,
                            height: h,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: avatar.avatarImageUrl != null
                                  ? Image.network(
                                      avatar.avatarImageUrl!,
                                      width: w,
                                      height: h,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildDefaultAvatar(),
                                    )
                                  : Container(
                                      color: const Color(0x1400DFA8),
                                      child: _buildDefaultAvatar(),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    // Avatar-Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nickname (falls vorhanden)
                          if (avatar.nickname != null &&
                              avatar.nickname!.isNotEmpty)
                            Text(
                              avatar.nickname!,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          // Vorname + Nachname (immer anzeigen)
                          Text(
                            [
                              avatar.firstName,
                              if (avatar.lastName != null &&
                                  avatar.lastName!.isNotEmpty)
                                avatar.lastName!,
                            ].join(' '),
                            style: TextStyle(
                              fontSize:
                                  (avatar.nickname != null &&
                                      avatar.nickname!.isNotEmpty)
                                  ? 16
                                  : 20,
                              fontWeight:
                                  (avatar.nickname != null &&
                                      avatar.nickname!.isNotEmpty)
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                              color:
                                  (avatar.nickname != null &&
                                      avatar.nickname!.isNotEmpty)
                                  ? Colors.grey.shade600
                                  : Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          _buildEmbedBadge(avatar.id),
                          // "Noch keine Nachrichten" ENTFERNT - nur wenn tatsächlich eine Message da ist
                          if (avatar.lastMessage != null &&
                              avatar.lastMessage!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              avatar.lastMessage!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      IconButton(
                        tooltip: 'Fakten prüfen',
                        style: IconButton.styleFrom(
                          overlayColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        icon: const Icon(
                          Icons.fact_check,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AvatarReviewFactsScreen(
                                avatarId: avatar.id,
                                fromScreen: 'avatar-list',
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: loc.t('gallery.title'),
                        style: IconButton.styleFrom(
                          overlayColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          await Navigator.pushNamed(
                            context,
                            '/media-gallery',
                            arguments: {
                              'avatarId': avatar.id,
                              'fromScreen': 'avatar-list',
                            },
                          );
                        },
                      ),
                      IconButton(
                        tooltip: loc.t('playlists.title'),
                        style: IconButton.styleFrom(
                          overlayColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        icon: const Icon(
                          Icons.playlist_play,
                          size: 20,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          await Navigator.pushNamed(
                            context,
                            '/playlist-list',
                            arguments: {
                              'avatarId': avatar.id,
                              'fromScreen': 'avatar-list',
                            },
                          );
                        },
                      ),
                      IconButton(
                        tooltip: loc.t('sharedMoments.title'),
                        style: IconButton.styleFrom(
                          overlayColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        icon: const Icon(
                          Icons.collections_bookmark_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          await Navigator.pushNamed(
                            context,
                            '/shared-moments',
                            arguments: {
                              'avatarId': avatar.id,
                              'fromScreen': 'avatar-list',
                            },
                          );
                        },
                      ),
                      IconButton(
                        tooltip: loc.t('avatars.editTooltip'),
                        style: IconButton.styleFrom(
                          overlayColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          await Navigator.pushNamed(
                            context,
                            '/avatar-details',
                            arguments: avatar,
                          );
                          if (!mounted) return;
                          await _loadAvatars();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // isPublic Toggle - oben rechts in der KACHEL (nicht im Bild)
          Positioned(
            top: 12,
            right: 12,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _togglePublic(avatar),
                child: Container(
                  width: 42,
                  height: 42,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFE91E63),
                        AppColors.lightBlue,
                        Color(0xFF00E5FF),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (avatar.isPublic ?? false)
                          ? Colors.transparent
                          : Colors.black.withValues(alpha: 0.85),
                    ),
                    child: Icon(
                      (avatar.isPublic ?? false) ? Icons.public : Icons.lock,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return const Icon(Icons.person, size: 30, color: AppColors.accentGreenDark);
  }

  // Entfernt: Zeitstempelanzeige wird aktuell nicht verwendet

  Future<void> _createNewAvatar() async {
    final result = await Navigator.pushNamed(context, '/avatar-creation');
    if (!mounted) return;
    if (result != null) {
      await _loadAvatars();
    }
  }

  void _openAvatarChat(model.AvatarData avatar) {
    Navigator.pushNamed(context, '/avatar-chat', arguments: avatar);
  }

  /// Toggle isPublic für Avatar
  Future<void> _togglePublic(model.AvatarData avatar) async {
    try {
      final newValue = !(avatar.isPublic ?? false);
      final updatedAvatar = avatar.copyWith(isPublic: newValue);

      // Optimistic UI Update
      setState(() {
        final index = _avatars.indexWhere((a) => a.id == avatar.id);
        if (index != -1) {
          _avatars[index] = updatedAvatar;
        }
        _applyFilter();
      });

      // Firestore Update
      await _avatarService.updateAvatar(updatedAvatar);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newValue
                  ? '✓ Avatar ist jetzt öffentlich sichtbar'
                  : '✓ Avatar ist jetzt privat',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Fehler beim Toggle isPublic: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
      // Bei Fehler: Liste neu laden
      _loadAvatars();
    }
  }
}
