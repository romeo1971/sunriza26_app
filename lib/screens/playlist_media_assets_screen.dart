import 'package:flutter/material.dart';
import '../models/media_models.dart';
import '../services/media_service.dart';
import '../theme/app_theme.dart';

class PlaylistMediaAssetsScreen extends StatefulWidget {
  final String avatarId;
  final List<AvatarMedia> preselected;
  const PlaylistMediaAssetsScreen({
    super.key,
    required this.avatarId,
    this.preselected = const [],
  });

  @override
  State<PlaylistMediaAssetsScreen> createState() =>
      _PlaylistMediaAssetsScreenState();
}

class _PlaylistMediaAssetsScreenState extends State<PlaylistMediaAssetsScreen> {
  final _mediaSvc = MediaService();
  List<AvatarMedia> _all = [];
  final List<String> _selected = [];
  String _tab = 'images';
  bool _portrait = true;
  final TextEditingController _search = TextEditingController();
  String _term = '';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(
      () => setState(() => _term = _search.text.toLowerCase()),
    );
  }

  Future<void> _load() async {
    final list = await _mediaSvc.list(widget.avatarId);
    setState(() {
      _all = list;
      _selected.addAll(widget.preselected.map((e) => e.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assets wählen'),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Abbrechen',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          IconButton(
            tooltip: 'Speichern',
            onPressed: _save,
            icon: const Icon(Icons.save),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(35),
          child: SizedBox(
            height: 35,
            child: Row(
              children: [
                _tabBtn('images', Icons.image_outlined),
                _tabBtn('videos', Icons.videocam_outlined),
                _tabBtn('documents', Icons.description_outlined),
                _tabBtn('audio', Icons.audiotrack),
                const Spacer(),
                SizedBox(
                  height: 32,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 180,
                      maxWidth: 180,
                    ),
                    child: TextField(
                      controller: _search,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Suche nach Medien...',
                        hintStyle: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.search,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 24,
                          maxWidth: 28,
                        ),
                        filled: true,
                        fillColor: Color(0x1FFFFFFF),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _portrait = !_portrait),
                  child: Icon(
                    _portrait
                        ? Icons.stay_primary_portrait
                        : Icons.stay_primary_landscape,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(padding: const EdgeInsets.all(12), child: _buildGrid()),
    );
  }

  Widget _tabBtn(String t, IconData icon) {
    final sel = _tab == t;
    final grad = Theme.of(context).extension<AppGradients>()?.magentaBlue;
    return SizedBox(
      height: 35,
      child: TextButton(
        onPressed: () => setState(() => _tab = t),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        child: sel
            ? Ink(
                decoration: BoxDecoration(gradient: grad),
                child: SizedBox(
                  width: 60,
                  height: double.infinity,
                  child: Icon(icon, color: Colors.white),
                ),
              )
            : SizedBox(
                width: 60,
                height: double.infinity,
                child: Icon(icon, color: Colors.white54),
              ),
      ),
    );
  }

  List<AvatarMedia> get _filtered {
    return _all.where((m) {
      switch (_tab) {
        case 'images':
          if (m.type != AvatarMediaType.image) return false;
          break;
        case 'videos':
          if (m.type != AvatarMediaType.video) return false;
          break;
        case 'documents':
          if (m.type != AvatarMediaType.document) return false;
          break;
        case 'audio':
          if (m.type != AvatarMediaType.audio) return false;
          break;
      }
      final ar = m.aspectRatio ?? 9 / 16;
      final isPortrait = ar < 1.0;
      final orientOk = _portrait ? isPortrait : !isPortrait;
      if (!orientOk) return false;
      if (_term.isEmpty) return true;
      final name = (m.originalFileName ?? m.url).toLowerCase();
      final tagsStr = (m.tags ?? []).map((t) => t.toLowerCase()).join(' ');
      return name.contains(_term) || tagsStr.contains(_term);
    }).toList();
  }

  Widget _buildGrid() {
    final items = _filtered;
    return LayoutBuilder(
      builder: (context, cons) {
        final col = (cons.maxWidth / 180).floor().clamp(2, 8);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: col,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final m = items[i];
            final sel = _selected.contains(m.id);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (sel) {
                    _selected.remove(m.id);
                  } else {
                    _selected.insert(0, m.id); // nach oben
                  }
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? Colors.lightGreenAccent : Colors.white24,
                    width: sel ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: Image.network(m.thumbUrl ?? m.url, fit: BoxFit.cover),
              ),
            );
          },
        );
      },
    );
  }

  void _save() {
    final result = _all.where((m) => _selected.contains(m.id)).toList();
    Navigator.pop(context, result);
  }
}
