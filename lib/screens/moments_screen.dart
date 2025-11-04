import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _svc.listMoments();
      if (!mounted) return;
      setState(() => _items = list);
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
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (context, i) {
                    final m = _items[i];
                    final subtitle = DateTime.fromMillisecondsSinceEpoch(m.acquiredAt)
                        .toLocal()
                        .toString();
                    return ListTile(
                      leading: Icon(
                        m.type == 'video'
                            ? Icons.videocam
                            : m.type == 'audio'
                                ? Icons.audiotrack
                                : Icons.photo,
                        color: AppColors.lightBlue,
                      ),
                      title: Text(
                        m.originalFileName ?? m.storedUrl.split('/').last,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                      onTap: () {
                        // Optional: Später Detail/Preview öffnen
                      },
                    );
                  },
                ),
    );
  }
}


