import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/moments_service.dart';
import '../models/moment.dart';
import '../theme/app_theme.dart';
import '../services/localization_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import '../widgets/moment_viewer.dart';

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
  // Pagination
  final int _pageSize = 10;
  int _page = 0; // 0-based

  // Filterzustände
  String? _selectedAvatarId; // null = alle
  final Set<String> _selectedTypes = {'image', 'video', 'audio', 'document'};
  final Map<String, String> _avatarNames = {}; // id -> display name
  final Map<String, String?> _avatarImageUrls = {}; // id -> hero image

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-Refresh wenn neue Momente erstellt/gelöscht wurden
    MomentsService.refreshTicker.addListener(_onMomentsChanged);
  }

  @override
  void dispose() {
    MomentsService.refreshTicker.removeListener(_onMomentsChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onMomentsChanged() {
    if (!mounted) return;
    _load();
  }
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _svc.listMoments();
      if (!mounted) return;
      setState(() => _items = list);

      // Avatar-Namen laden für Dropdown (Cache vorher löschen für frische Daten)
      _avatarNames.clear();
      _avatarImageUrls.clear();
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
      debugPrint('🔵 [Moments] Loading avatar names for IDs: $ids');
      for (final id in ids) {
        if (id.isEmpty) continue;
        if (_avatarNames.containsKey(id) && _avatarImageUrls.containsKey(id)) {
          debugPrint('🔵 [Moments] Skipping cached avatar: $id');
          continue;
        }
        debugPrint('🔵 [Moments] Fetching avatar doc: $id');
        final doc = await FirebaseFirestore.instance.collection('avatars').doc(id).get();
        if (doc.exists) {
          final d = doc.data() ?? {};
          _avatarImageUrls[id] = (d['avatarImageUrl'] as String?);
          debugPrint('✅ [Moments] Avatar $id → image: ${_avatarImageUrls[id]}');
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
      // Typ-Defensiv: akzeptiere Aliasse (pdf/doc/documents)
      final t = (m.type).toLowerCase();
      final norm = (t == 'documents' || t == 'pdf' || t == 'doc') ? 'document' : t;
      if (!_selectedTypes.contains(norm)) return false;
      if (q.isEmpty) return true;
      final inName = (m.originalFileName ?? '').toLowerCase().contains(q);
      final inTags = (m.tags ?? const []).any((t) => t.toLowerCase().contains(q));
      final inUrl = m.storedUrl.toLowerCase().contains(q);
      return inName || inTags || inUrl;
    }).toList();
  }

  List<Moment> get _visibleItems {
    final list = _filteredItems;
    final start = (_page * _pageSize).clamp(0, list.length);
    final end = (start + _pageSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Momente', style: TextStyle(color: Colors.white)),
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
                          // Avatar Dropdown (fixe Breite, um Overflow zu vermeiden)
                          SizedBox(
                            width: 140,
                            child: FutureBuilder<List<MapEntry<String, String>>>(
                              future: _getAvatarDropdownItems(),
                              builder: (context, snapshot) {
                                final avatars = snapshot.data ?? [];
                                return DropdownButtonFormField<String?>(
                                  initialValue: _selectedAvatarId,
                                  dropdownColor: Colors.black87,
                                  decoration: const InputDecoration(
                                    labelText: 'Avatar',
                                    labelStyle: TextStyle(color: Colors.white70),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Alle', style: TextStyle(color: Colors.white)),
                                    ),
                                    ...avatars.map((e) {
                                      return DropdownMenuItem<String?>(
                                        value: e.key,
                                        child: FutureBuilder<String?>(
                                          future: _getAvatarImage(e.key),
                                          builder: (context, imgSnap) {
                                            final img = imgSnap.data;
                                            return Row(
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
                                                Text(e.value, style: const TextStyle(color: Colors.white)),
                                              ],
                                            );
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: (v) => setState(() => _selectedAvatarId = v),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Suche
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() { _page = 0; }),
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Suche (Name, Tags, URL)',
                                hintStyle: TextStyle(color: Colors.white38),
                                prefixIcon: Icon(Icons.search, color: Colors.white54),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Typenfilter (nur Icons) – mobil horizontal scrollbar, mehr Abstand
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _typeIcon('image', Icons.image, 'Bilder'),
                            const SizedBox(width: 16),
                            _typeIcon('video', Icons.videocam, 'Videos'),
                            const SizedBox(width: 16),
                            _typeIcon('document', Icons.description, 'Dokumente'),
                            const SizedBox(width: 16),
                            _typeIcon('audio', Icons.audiotrack, 'Audio'),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    // Liste
                    Expanded(
                      child: ListView.separated(
                        itemCount: _visibleItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (context, i) {
                          final m = _visibleItems[i];
                          final avatarName = _avatarNames[m.avatarId] ?? 'Avatar';
                          final dt = DateTime.fromMillisecondsSinceEpoch(m.acquiredAt).toLocal();
                          final subtitle = DateFormat('yyyy-MM-dd HH:mm').format(dt);

                          return FutureBuilder<String?>(
                            future: _getAvatarImage(m.avatarId),
                            builder: (context, snapshot) {
                              final avatarImg = snapshot.data;
                              final remaining = (m.maxDownloads ?? 5) - (m.downloadCount ?? 0);
                              final canDownload = remaining > 0;
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
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Payment Badge
                                    if (m.price != null && m.price! > 0.0 && m.paymentMethod != null)
                                      _buildPaymentBadge(m.paymentMethod!),
                                    const SizedBox(width: 8),
                                    // Downloads verbleibend
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'DL: ${remaining.clamp(0, 5)}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Download Icon
                                    IconButton(
                                      tooltip: canDownload ? 'Download' : 'Limit erreicht',
                                      onPressed: canDownload
                                          ? () async {
                                              final url = (m.storedUrl.isNotEmpty) ? m.storedUrl : m.originalUrl;
                                              try {
                                                final uri = Uri.parse(url);
                                                if (await canLaunchUrl(uri)) {
                                                  await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
                                                }
                                              } catch (_) {}
                                              // Zähler erhöhen
                                              try {
                                                final left = await _svc.incrementDownloadCount(m.id);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Download gestartet • verbleibend: $left')),
                                                  );
                                                  _onMomentsChanged();
                                                }
                                              } catch (_) {}
                                            }
                                          : null,
                                      icon: Icon(Icons.download,
                                          color: canDownload ? Colors.lightBlueAccent : Colors.white24),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right, color: Colors.white54),
                                  ],
                                ),
                                onTap: () {
                                  // Fullscreen Viewer über aktuell gefilterte Liste
                                  final all = _filteredItems; // gesamte Ansicht (nicht nur Seite)
                                  final idx = all.indexWhere((e) => e.id == m.id);
                                  if (idx >= 0) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => MomentViewer(moments: all, initialIndex: idx),
                                        fullscreenDialog: true,
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // Pagination-Leiste
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: _page > 0 ? () => setState(() => _page--) : null,
                            child: const Text('Zurück'),
                          ),
                          const SizedBox(width: 8),
                          Builder(builder: (_) {
                            final total = _filteredItems.length;
                            if (total == 0) return const SizedBox();
                            final start = (_page * _pageSize) + 1;
                            final end = ((_page * _pageSize) + _pageSize).clamp(1, total);
                            return Text('$start–$end/$total', style: const TextStyle(color: Colors.white70));
                          }),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: ((_page + 1) * _pageSize) < _filteredItems.length
                                ? () => setState(() => _page++)
                                : null,
                            child: const Text('Weiter'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<String?> _getAvatarImage(String avatarId) async {
    if (avatarId.isEmpty) return null;
    if (_avatarImageUrls.containsKey(avatarId)) return _avatarImageUrls[avatarId];
    try {
      final doc = await FirebaseFirestore.instance.collection('avatars').doc(avatarId).get();
      if (doc.exists) {
        final img = doc.data()?['avatarImageUrl'] as String?;
        _avatarImageUrls[avatarId] = img;
        return img;
      }
    } catch (_) {}
    return null;
  }

  Future<List<MapEntry<String, String>>> _getAvatarDropdownItems() async {
    final ids = _items.map((e) => e.avatarId).where((id) => id.isNotEmpty).toSet();
    final List<MapEntry<String, String>> result = [];
    for (final id in ids) {
      try {
        final doc = await FirebaseFirestore.instance.collection('avatars').doc(id).get();
        if (doc.exists) {
          final d = doc.data() ?? {};
          final nickname = (d['nickname'] as String?)?.trim();
          final firstName = (d['firstName'] as String?)?.trim();
          final name = (nickname?.isNotEmpty ?? false) ? nickname! : (firstName ?? 'Avatar');
          result.add(MapEntry(id, name));
        }
      } catch (_) {}
    }
    return result;
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

  // Icon-basierter Typ-Filter (ohne Haken):
  // unselected → transparenter Hintergrund, graue Icons, graue Border
  // selected → GMBC Gradient, Icon weiß
  Widget _typeIcon(String key, IconData icon, String tooltip) {
    final selected = _selectedTypes.contains(key);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => setState(() {
          if (selected) {
            _selectedTypes.remove(key);
            if (_selectedTypes.isEmpty) {
              _selectedTypes.add(key); // mindestens ein Typ aktiv
            }
          } else {
            _selectedTypes.add(key);
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFE91E63), AppColors.lightBlue, Color(0xFF00E5FF)],
                  )
                : null,
            color: selected ? null : Colors.transparent,
            border: Border.all(
              color: selected ? Colors.white70 : Colors.white38,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(icon, color: selected ? Colors.white : Colors.white60, size: 20),
        ),
      ),
    );
  }

  /// Badge für Zahlungsmethode
  Widget _buildPaymentBadge(String paymentMethod) {
    if (paymentMethod == 'credits') {
      return ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Color(0xFFE91E63),
            AppColors.lightBlue,
            Color(0xFF00E5FF),
          ],
        ).createShader(bounds),
        child: const Icon(
          Icons.diamond,
          color: Colors.white,
          size: 20,
        ),
      );
    } else if (paymentMethod == 'stripe') {
      return const Icon(
        Icons.attach_money,
        color: Colors.green,
        size: 20,
      );
    }
    return const SizedBox.shrink();
  }
}


