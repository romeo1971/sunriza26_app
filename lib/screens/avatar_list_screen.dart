import 'package:flutter/material.dart';
import '../models/avatar_data.dart' as model;
import '../widgets/app_drawer.dart';

class AvatarListScreen extends StatefulWidget {
  const AvatarListScreen({super.key});

  @override
  State<AvatarListScreen> createState() => _AvatarListScreenState();
}

class _AvatarListScreenState extends State<AvatarListScreen> {
  // TODO: Replace with actual data from Firestore
  final List<model.AvatarData> _avatars = [
    model.AvatarData(
      id: '1',
      userId: 'demo',
      firstName: 'Oma Maria',
      nickname: 'Oma',
      avatarImageUrl: null,
      imageUrls: const [],
      videoUrls: const [],
      textFileUrls: const [],
      writtenTexts: const [],
      lastMessage: 'Wie geht es dir heute?',
      lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    model.AvatarData(
      id: '2',
      userId: 'demo',
      firstName: 'Opa Hans',
      nickname: 'Opa',
      avatarImageUrl: null,
      imageUrls: const [],
      videoUrls: const [],
      textFileUrls: const [],
      writtenTexts: const [],
      lastMessage: 'Erzähl mir von deinem Tag',
      lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Meine Avatare'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _createNewAvatar,
            icon: const Icon(Icons.add),
            tooltip: 'Neuen Avatar erstellen',
          ),
        ],
      ),
      body: _avatars.isEmpty ? _buildEmptyState() : _buildAvatarList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewAvatar,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Neuer Avatar'),
      ),
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
                color: Colors.deepPurple.shade100,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.deepPurple.shade300, width: 2),
              ),
              child: Icon(
                Icons.person_add,
                size: 60,
                color: Colors.deepPurple.shade300,
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
                backgroundColor: Colors.deepPurple,
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
              // Avatar-Bild
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepPurple.shade100,
                  border: Border.all(
                    color: Colors.deepPurple.shade300,
                    width: 2,
                  ),
                ),
                child: avatar.avatarImageUrl != null
                    ? ClipOval(
                        child: Image.network(
                          avatar.avatarImageUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildDefaultAvatar(),
                        ),
                      )
                    : _buildDefaultAvatar(),
              ),

              const SizedBox(width: 16),

              // Avatar-Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (avatar.nickname != null && avatar.nickname!.isNotEmpty)
                          ? avatar.nickname!
                          : avatar.firstName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (avatar.nickname != null &&
                        avatar.nickname!.isNotEmpty &&
                        avatar.nickname != avatar.firstName)
                      Text(
                        avatar.firstName,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      avatar.lastMessage ?? 'Noch keine Nachrichten',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Zeit und Pfeil
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(avatar.lastMessageTime ?? DateTime.now()),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 8),
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
    return Icon(Icons.person, size: 30, color: Colors.deepPurple.shade300);
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'Jetzt';
    }
  }

  void _createNewAvatar() {
    Navigator.pushNamed(context, '/avatar-upload');
  }

  void _openAvatarChat(model.AvatarData avatar) {
    Navigator.pushNamed(context, '/avatar-chat', arguments: avatar);
  }
}
