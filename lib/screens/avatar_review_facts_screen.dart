import 'package:flutter/material.dart';
import 'package:sunriza26/services/fact_review_service.dart';
import 'package:provider/provider.dart';
import 'package:sunriza26/services/localization_service.dart';
import '../widgets/avatar_nav_bar.dart';
import '../widgets/avatar_bottom_nav_bar.dart';
import '../services/avatar_service.dart';

class AvatarReviewFactsScreen extends StatefulWidget {
  final String avatarId;
  final String? fromScreen; // 'avatar-list' oder null

  const AvatarReviewFactsScreen({
    super.key,
    required this.avatarId,
    this.fromScreen,
  });

  @override
  State<AvatarReviewFactsScreen> createState() =>
      _AvatarReviewFactsScreenState();
}

class _AvatarReviewFactsScreenState extends State<AvatarReviewFactsScreen> {
  final FactReviewService _service = FactReviewService();
  final ScrollController _scrollController = ScrollController();

  List<FactItem> _facts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int? _cursor;
  String _statusFilter = 'pending';
  final Set<String> _processing = {};
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchFacts(reset: true);
    _scrollController.addListener(() {
      _onScroll();
      setState(() => _scrollOffset = _scrollController.offset);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchFacts({bool reset = false}) async {
    if (_isLoading || _isLoadingMore) return;
    setState(() {
      if (reset) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });
    try {
      final response = await _service.fetchFacts(
        widget.avatarId,
        status: _statusFilter,
        cursor: reset ? null : _cursor,
      );
      setState(() {
        if (reset) {
          _facts = response.items;
        } else {
          _facts.addAll(response.items);
        }
        _hasMore = response.hasMore;
        _cursor = response.nextCursor;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fakten konnten nicht geladen werden: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _fetchFacts();
    }
  }

  Future<void> _changeStatus(FactItem item, String status) async {
    if (_processing.contains(item.factId)) return;
    setState(() {
      _processing.add(item.factId);
    });

    try {
      final updated = await _service.updateFact(
        widget.avatarId,
        factId: item.factId,
        newStatus: status,
      );
      setState(() {
        _processing.remove(item.factId);
        _facts = _facts
            .map((f) => f.factId == updated.factId ? updated : f)
            .toList();
        if (_statusFilter != updated.status) {
          _facts.removeWhere((f) => f.factId == updated.factId);
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'Fakt freigegeben'
                : (status == 'rejected'
                      ? 'Fakt abgelehnt'
                      : 'Fakt aktualisiert'),
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _processing.remove(item.factId);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aktualisierung fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _onFilterChanged(String status) async {
    setState(() {
      _statusFilter = status;
      _cursor = null;
      _facts = [];
      _hasMore = false;
    });
    await _fetchFacts(reset: true);
  }

  void _handleBackNavigation(BuildContext context) async {
    if (widget.fromScreen == 'avatar-list') {
      // Von "Meine Avatare" → zurück zu "Meine Avatare" (ALLE Screens schließen)
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/avatar-list',
        (route) => false,
      );
    } else {
      // Von anderen Screens → zurück zu Avatar Details
      final avatarService = AvatarService();
      final avatar = await avatarService.getAvatar(widget.avatarId);
      if (avatar != null && context.mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/avatar-details',
          arguments: avatar,
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (_scrollOffset / 150.0).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faktenfreigabe'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackNavigation(context),
        ),
      ),
      body: Column(
        children: [
          const SizedBox.shrink(),
          _buildFilterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchFacts(reset: true),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _facts.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Keine Fakten gefunden.')),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: _facts.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _facts.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final fact = _facts[index];
                        final processing = _processing.contains(fact.factId);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: const Color(0xFF111111),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fact.factText,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    _buildChip(
                                      'Confidence: ${(fact.confidence * 100).toStringAsFixed(0)}%',
                                    ),
                                    _buildChip('Scope: ${fact.scope}'),
                                    _buildChip(
                                      context.read<LocalizationService>().t(
                                        'facts.status.${fact.status}',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (fact.authorDisplayName != null ||
                                    fact.authorEmail != null)
                                  Text(
                                    'Quelle: ${fact.authorDisplayName ?? ''} ${fact.authorEmail ?? ''}'
                                        .trim(),
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (fact.history.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Historie',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: fact.history
                                        .map(
                                          (h) => Text(
                                            '${DateTime.fromMillisecondsSinceEpoch(h.at).toLocal()} - ${h.action}${h.note != null ? ' (${h.note})' : ''}',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 11,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    if (_statusFilter == 'pending') ...[
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: processing
                                              ? null
                                              : () => _changeStatus(
                                                  fact,
                                                  'approved',
                                                ),
                                          icon: processing
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 1.5,
                                                      ),
                                                )
                                              : const Icon(Icons.check),
                                          label: const Text('Freigeben'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.green.shade600,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: processing
                                              ? null
                                              : () => _changeStatus(
                                                  fact,
                                                  'rejected',
                                                ),
                                          icon: const Icon(Icons.close),
                                          label: const Text('Ablehnen'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.red.shade600,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: processing
                                              ? null
                                              : () => _changeStatus(
                                                  fact,
                                                  'deleted',
                                                ),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Löschen'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.red.shade700,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AvatarBottomNavBar(
        avatarId: widget.avatarId,
        currentScreen: 'facts',
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            context.read<LocalizationService>().t('Status:'),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _statusFilter,
            dropdownColor: const Color(0xFF1C1C1E),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white),
            items: [
              DropdownMenuItem(
                value: 'pending',
                child: Text(
                  context.read<LocalizationService>().t('facts.status.pending'),
                ),
              ),
              DropdownMenuItem(
                value: 'approved',
                child: Text(
                  context.read<LocalizationService>().t(
                    'facts.status.approved',
                  ),
                ),
              ),
              DropdownMenuItem(
                value: 'rejected',
                child: Text(
                  context.read<LocalizationService>().t(
                    'facts.status.rejected',
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              if (value == null || value == _statusFilter) return;
              _onFilterChanged(value);
            },
          ),
          const Spacer(),
          IconButton(
            tooltip: context.read<LocalizationService>().t(
              'avatars.refreshTooltip',
            ),
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _fetchFacts(reset: true),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
