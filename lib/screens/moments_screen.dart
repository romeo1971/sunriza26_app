import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/moments_service.dart';
import '../models/moment.dart';
import '../theme/app_theme.dart';
import '../services/localization_service.dart';

/// MomentsScreen – zeigt die vom Nutzer angenommenen/gekauften Medien
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final _svc = MomentsService();
  bool _loading = true;
  List<Moment> _items = [];
  final TextEditingController _searchCtrl = TextEditingController();

  // Filterzustände
  String? _selectedAvatarId; // null = alle
  final Set<String> _selectedTypes = {'image', 'video', 'audio', 'document'};
  final Map<String, String> _avatarNames = {}; // id -> display name
  final Map<String, String?> _avatarImageUrls = {}; // id -> hero image

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _svc.listMoments();
      if (!mounted) return;
      setState(() => _items = list);

      // Avatar-Namen laden für Dropdown
      final ids = list.map((e) => e.avatarId).toSet();
      await _loadAvatarNames(ids);
    } catch (_) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('general.loadError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAvatarNames(Set<String> ids) async {
    try {
      for (final id in ids) {
        if (_avatarNames.containsKey(id)) continue;
        final doc = await FirebaseFirestore.instance.collection('avatars').doc(id).get();
        if (doc.exists) {
          final d = doc.data() ?? {};
          _avatarImageUrls[id] = (d['avatarImageUrl'] as String?);
          final nickname = (d['nickname'] as String?)?.trim();
          final firstName = (d['firstName'] as String?)?.trim();
          final lastName = (d['lastName'] as String?)?.trim();
          final nicknamePublic = (d['nicknamePublic'] as String?)?.trim();
          final firstNamePublic = (d['firstNamePublic'] as String?)?.trim();
          final lastNamePublic = (d['lastNamePublic'] as String?)?.trim();
          String name = (nickname?.isNotEmpty ?? false)
              ? nickname!
              : (firstName ?? '');
          if (name.isEmpty) {
            final parts = <String>[];
            if (firstName != null && firstName.isNotEmpty) parts.add(firstName);
            if (lastName != null && lastName.isNotEmpty) parts.add(lastName);
            if (parts.isEmpty) {
              if (nicknamePublic != null && nicknamePublic.isNotEmpty) {
                parts.add(nicknamePublic);
              } else {
                if (firstNamePublic != null && firstNamePublic.isNotEmpty) parts.add(firstNamePublic);
                if (lastNamePublic != null && lastNamePublic.isNotEmpty) parts.add(lastNamePublic);
              }
            }
            name = parts.join(' ').trim();
          }
          _avatarNames[id] = name.isEmpty ? 'Avatar' : name;
        } else {
          _avatarImageUrls[id] = null;
          _avatarNames[id] = 'Avatar';
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Moment> get _filteredItems {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((m) {
      if (_selectedAvatarId != null && m.avatarId != _selectedAvatarId) return false;
      if (!_selectedTypes.contains(m.type)) return false;
      if (q.isEmpty) return true;
      final inName = (m.originalFileName ?? '').toLowerCase().contains(q);
      final inTags = (m.tags ?? const []).any((t) => t.toLowerCase().contains(q));
      final inUrl = m.storedUrl.toLowerCase().contains(q);
      return inName || inTags || inUrl;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Momente'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text(
                    'Noch keine Momente gespeichert',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : Column(
                  children: [
                    // Filterleiste
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          // Avatar Dropdown
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _selectedAvatarId,
                              dropdownColor: Colors.black87,
                              decoration: const InputDecoration(
                                labelText: 'Avatar',
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Alle', style: TextStyle(color: Colors.white)),
                                ),
                                ..._avatarNames.entries.map((e) {
                                  final img = _avatarImageUrls[e.key];
                                  return DropdownMenuItem<String?>(
                                    value: e.key,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Colors.white12,
                                          backgroundImage: (img != null && img.isNotEmpty)
                                              ? NetworkImage(img)
                                              : null,
                                          child: (img == null || img.isEmpty)
                                              ? const Icon(Icons.person, size: 16, color: Colors.white54)
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          (e.value.isEmpty ? 'Avatar' : e.value),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (v) => setState(() => _selectedAvatarId = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Suche
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Suche (Name, Tags, URL)',
                                hintStyle: TextStyle(color: Colors.white38),
                                prefixIcon: Icon(Icons.search, color: Colors.white54),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Typenfilter
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          _typeChip('image', 'Bilder'),
                          _typeChip('video', 'Videos'),
                          _typeChip('audio', 'Audio'),
                          _typeChip('document', 'Dokumente'),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    // Liste
                    Expanded(
                      child: ListView.separated(
                        itemCount: _filteredItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (context, i) {
                    final m = _filteredItems[i];
                    final avatarImg = _avatarImageUrls[m.avatarId];
                    final avatarName = _avatarNames[m.avatarId] ?? 'Avatar';
                    final dt = DateTime.fromMillisecondsSinceEpoch(m.acquiredAt).toLocal();
                    final subtitle = DateFormat('yyyy-MM-dd HH:mm').format(dt);
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white12,
                        backgroundImage: (avatarImg != null && avatarImg.isNotEmpty)
                            ? NetworkImage(avatarImg)
                            : null,
                        child: (avatarImg == null || avatarImg.isEmpty)
                            ? const Icon(Icons.person, color: Colors.white54)
                            : null,
                      ),
                      title: Text(
                        m.originalFileName ?? m.storedUrl.split('/').last,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '$avatarName  •  $subtitle',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                      onTap: () {
                        // Optional: Später Detail/Preview öffnen
                      },
                    );
                  },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _typeChip(String key, String label) {
    final selected = _selectedTypes.contains(key);
    return FilterChip(
      selected: selected,
      onSelected: (_) => setState(() {
        if (selected) {
          _selectedTypes.remove(key);
          if (_selectedTypes.isEmpty) {
            // Immer mindestens ein Typ aktiv lassen
            _selectedTypes.add(key);
          }
        } else {
          _selectedTypes.add(key);
        }
      }),
      label: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white70)),
      selectedColor: AppColors.lightBlue,
      backgroundColor: Colors.white12,
      checkmarkColor: Colors.black,
    );
  }
}


