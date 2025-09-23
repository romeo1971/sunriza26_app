import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/avatar_data.dart' as model;
import '../widgets/app_drawer.dart';
import '../services/avatar_service.dart';

class AvatarListScreen extends StatefulWidget {
  const AvatarListScreen({super.key});

  @override
  State<AvatarListScreen> createState() => _AvatarListScreenState();
}

class _AvatarListScreenState extends State<AvatarListScreen> {
  final AvatarService _avatarService = AvatarService();
  List<model.AvatarData> _avatars = [];
  bool _isLoading = true;

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
    } on FirebaseException catch (e) {
      if (mounted) {
        final msg = e.code == 'failed-precondition'
            ? 'Firestore-Index fehlt. Führe: firebase deploy --only firestore:indexes'
            : e.message ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Avatare: $msg')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Avatare: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Meine Avatare'),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Avatar Editor wird jetzt über Avatar Details aufgerufen
          IconButton(
            onPressed: _loadAvatars,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
          ),
          if (!_isLoading && _avatars.isNotEmpty)
            IconButton(
              onPressed: _createNewAvatar,
              icon: const Icon(Icons.add),
              tooltip: 'Neuen Avatar erstellen',
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0x1400DFA8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accentGreenDark.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.person_add,
                size: 60,
                color: AppColors.accentGreenDark,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Noch keine Avatare',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Erstelle deinen ersten Avatar und beginne eine besondere Unterhaltung',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _createNewAvatar,
              icon: const Icon(Icons.add),
              label: const Text('Ersten Avatar erstellen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreenDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _avatars.length,
      itemBuilder: (context, index) {
        final avatar = _avatars[index];
        return _buildAvatarCard(avatar);
      },
    );
  }

  Widget _buildAvatarCard(model.AvatarData avatar) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _openAvatarChat(avatar),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar-Bild 9:16 (ca. 2.5x höher)
              Builder(
                builder: (context) {
                  const double h = 150; // ~2.5 * 60
                  const double w = h * 9 / 16;
                  return Container(
                    width: w,
                    height: h,
                    decoration: BoxDecoration(
                      color: const Color(0x1400DFA8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.accentGreenDark,
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: avatar.avatarImageUrl != null
                        ? Image.network(
                            avatar.avatarImageUrl!,
                            width: w,
                            height: h,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildDefaultAvatar(),
                          )
                        : _buildDefaultAvatar(),
                  );
                },
              ),

              const SizedBox(width: 16),

              // Avatar-Info + BP-Hinweis
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (avatar.nickname != null &&
                                    avatar.nickname!.isNotEmpty)
                                ? avatar.nickname!
                                : avatar.firstName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final tr = Map<String, dynamic>.from(
                              avatar.training ?? {},
                            );
                            final provider = (tr['videoProvider'] as String?)
                                ?.toLowerCase();
                            final bp = Map<String, dynamic>.from(
                              tr['beyondPresence'] ?? {},
                            );
                            final hasAvatarId =
                                ((bp['avatarId'] as String?)
                                    ?.trim()
                                    .isNotEmpty ??
                                false);
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                    if (avatar.nickname != null &&
                        avatar.nickname!.isNotEmpty &&
                        avatar.nickname != avatar.firstName)
                      Text(
                        (avatar.nickname != null && avatar.nickname!.isNotEmpty)
                            ? avatar.firstName
                            : '',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      avatar.lastMessage ?? 'Noch keine Nachrichten',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade400,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Edit und Pfeil
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Avatar bearbeiten',
                    icon: const Icon(Icons.edit, size: 18, color: Colors.white),
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
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
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
}
