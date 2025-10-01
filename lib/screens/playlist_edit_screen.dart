import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'dart:io';
import 'dart:typed_data';
import '../models/playlist_models.dart';
import '../services/playlist_service.dart';
import '../services/media_service.dart';
import '../models/media_models.dart';

class PlaylistEditScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistEditScreen({super.key, required this.playlist});

  @override
  State<PlaylistEditScreen> createState() => _PlaylistEditScreenState();
}

class _PlaylistEditScreenState extends State<PlaylistEditScreen> {
  late TextEditingController _name;
  late TextEditingController _showAfter;
  late TextEditingController _highlightTag;
  final _svc = PlaylistService();
  final _mediaSvc = MediaService();
  List<PlaylistItem> _items = [];
  Map<String, AvatarMedia> _mediaMap = {};
  
  // Cover Image State
  String? _coverImageUrl;
  bool _uploadingCover = false;
  
  // Weekly Schedule State: Map<Weekday, Set<TimeSlot>>
  final Map<int, Set<TimeSlot>> _weeklySchedule = {};
  
  // Special Schedules State
  List<SpecialSchedule> _specialSchedules = [];
  
  // UI State: aktuell gewählter Wochentag für Zeitfenster-Auswahl
  int? _selectedWeekday;
  
  // UI State: Wöchentlicher Zeitplan aufgeklappt?
  bool _weeklyScheduleExpanded = true;
  
  // UI State: Highlight-Tag Bereich aufgeklappt?
  bool _highlightTagExpanded = false;
  
  // Vordefinierte Highlight-Tags
  static const List<String> _predefinedTags = [
    'Geburtstag',
    'Namenstag',
    'Weihnachten',
    'Ostern',
    'Neujahr',
    'Valentinstag',
    'Muttertag',
    'Vatertag',
    'Silvester',
    'Hochzeitstag',
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.playlist.name);
    _showAfter = TextEditingController(
      text: widget.playlist.showAfterSec.toString(),
    );
    _highlightTag = TextEditingController(text: widget.playlist.highlightTag ?? '');
    _coverImageUrl = widget.playlist.coverImageUrl;
    
    // Initialize weekly schedule from playlist
    for (final ws in widget.playlist.weeklySchedules) {
      _weeklySchedule[ws.weekday] = Set.from(ws.timeSlots);
    }
    
    _specialSchedules = List.from(widget.playlist.specialSchedules);
    _load();
  }

  Future<void> _load() async {
    final items = await _svc.listItems(
      widget.playlist.avatarId,
      widget.playlist.id,
    );
    final medias = await _mediaSvc.list(widget.playlist.avatarId);
    setState(() {
      _items = items;
      _mediaMap = {for (final m in medias) m.id: m};
    });
  }

  Future<File?> _cropToPortrait916(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final cropController = cyi.CropController();
      Uint8List? result;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          backgroundColor: Colors.black,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: LayoutBuilder(
            builder: (dCtx, _) {
              final sz = MediaQuery.of(dCtx).size;
              final double dlgW = (sz.width * 0.9).clamp(320.0, 900.0);
              final double dlgH = (sz.height * 0.9).clamp(480.0, 1200.0);
              return SizedBox(
                width: dlgW,
                height: dlgH,
                child: Column(
                  children: [
                    Expanded(
                      child: cyi.Crop(
                        controller: cropController,
                        image: bytes,
                        aspectRatio: 9 / 16,
                        withCircleUi: false,
                        baseColor: Colors.black,
                        maskColor: Colors.black38,
                        onCropped: (cropped) {
                          result = cropped;
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => cropController.crop(),
                        child: const Text('Zuschneiden'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      if (result == null) return null;
      final tmp = File('${input.path}.cropped.png');
      await tmp.writeAsBytes(result!, flush: true);
      return tmp;
    } catch (e) {
      return null;
    }
  }

  Future<void> _uploadCoverImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    File f = File(pickedFile.path);
    final cropped = await _cropToPortrait916(f);
    if (cropped != null) f = cropped;

    setState(() => _uploadingCover = true);

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('avatars/${widget.playlist.avatarId}/playlists/${widget.playlist.id}/cover.jpg');
      
      await ref.putFile(f);
      final url = await ref.getDownloadURL();
      
      setState(() {
        _coverImageUrl = url;
        _uploadingCover = false;
      });
    } catch (e) {
      setState(() => _uploadingCover = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Upload: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    final highlightText = _highlightTag.text.trim();
    
    // Convert Map to List<WeeklySchedule>, FILTER OUT empty timeslots
    final weeklySchedules = _weeklySchedule.entries
        .where((e) => e.value.isNotEmpty) // NUR Wochentage mit mind. 1 Zeitfenster
        .map((e) => WeeklySchedule(weekday: e.key, timeSlots: e.value.toList()))
        .toList();
    
    print('🔍 DEBUG: Saving weeklySchedules: ${weeklySchedules.length} entries');
    for (final ws in weeklySchedules) {
      print('   - Weekday ${ws.weekday}: ${ws.timeSlots.map((t) => t.index).toList()}');
    }
    print('🔍 DEBUG: Saving specialSchedules: ${_specialSchedules.length} entries');
    
    final p = Playlist(
      id: widget.playlist.id,
      avatarId: widget.playlist.avatarId,
      name: _name.text.trim(),
      showAfterSec: int.tryParse(_showAfter.text.trim()) ?? 0,
      highlightTag: highlightText.isNotEmpty ? highlightText : null,
      coverImageUrl: _coverImageUrl,
      weeklySchedules: weeklySchedules,
      specialSchedules: _specialSchedules,
      createdAt: widget.playlist.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    
    print('🔍 DEBUG: Playlist.toMap() keys: ${p.toMap().keys}');
    print('🔍 DEBUG: weeklySchedules in map: ${p.toMap()['weeklySchedules']}');
    
    await _svc.update(p);
    if (mounted) Navigator.pop(context, true); // Return true to trigger refresh
  }

  void _toggleTimeSlot(int weekday, TimeSlot slot) {
    setState(() {
      _weeklySchedule.putIfAbsent(weekday, () => <TimeSlot>{});
      if (_weeklySchedule[weekday]!.contains(slot)) {
        _weeklySchedule[weekday]!.remove(slot);
        if (_weeklySchedule[weekday]!.isEmpty) {
          _weeklySchedule.remove(weekday);
        }
      } else {
        _weeklySchedule[weekday]!.add(slot);
      }
    });
  }

  String _timeSlotLabel(TimeSlot slot) {
    switch (slot) {
      case TimeSlot.earlyMorning:
        return '3-6 Uhr';
      case TimeSlot.morning:
        return '6-11 Uhr';
      case TimeSlot.noon:
        return '11-14 Uhr';
      case TimeSlot.afternoon:
        return '14-18 Uhr';
      case TimeSlot.evening:
        return '18-23 Uhr';
      case TimeSlot.night:
        return '23-3 Uhr';
    }
  }
  
  String _timeSlotIcon(TimeSlot slot) {
    switch (slot) {
      case TimeSlot.earlyMorning:
        return '🌅';
      case TimeSlot.morning:
        return '☀️';
      case TimeSlot.noon:
        return '🌞';
      case TimeSlot.afternoon:
        return '🌤️';
      case TimeSlot.evening:
        return '🌆';
      case TimeSlot.night:
        return '🌙';
    }
  }

  String _weekdayLabel(int weekday) {
    const labels = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    return labels[weekday - 1];
  }
  
  String _weekdayShort(int weekday) {
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return labels[weekday - 1];
  }
  
  bool _canSelectWeekday(int weekday) {
    // Wochentag kann gewählt werden, wenn noch nicht alle Zeitfenster belegt sind
    final existing = _weeklySchedule[weekday];
    return existing == null || existing.length < 6;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist bearbeiten'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.save))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image Upload
            const Text('Cover-Bild (9:16)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _uploadingCover ? null : _uploadCoverImage,
              child: Container(
                width: 120,
                height: 213, // 9:16 aspect ratio
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade600),
                ),
                child: _uploadingCover
                    ? const Center(child: CircularProgressIndicator())
                    : _coverImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _coverImageUrl!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.add_photo_alternate, size: 40, color: Colors.white54),
                          ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Name
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            
            // Show After
            TextField(
              controller: _showAfter,
              decoration: const InputDecoration(
                labelText: 'Allgemeine Anzeigezeit (Sekunden) nach Chat-Beginn',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            
            // Highlight Tag Section (Collapsible)
            InkWell(
              onTap: () {
                setState(() {
                  _highlightTagExpanded = !_highlightTagExpanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Highlight-Tag',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      if (_highlightTag.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber),
                            ),
                            child: Text(
                              _highlightTag.text,
                              style: const TextStyle(fontSize: 11, color: Colors.amber),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Icon(
                    _highlightTagExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 28,
                  ),
                ],
              ),
            ),
            if (_highlightTagExpanded) ...[
              const SizedBox(height: 12),
              const Text(
                'Vordefinierte Anlässe',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _predefinedTags.map((tag) {
                  final isSelected = _highlightTag.text == tag;
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _highlightTag.clear();
                          } else {
                            _highlightTag.text = tag;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.amber.withOpacity(0.3) : Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Colors.amber : Colors.grey.shade600,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.amber : Colors.white70,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Eigenes Tag',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _highlightTag,
                decoration: const InputDecoration(
                  labelText: 'Eigener Anlass',
                  hintText: 'z.B. Firmenjubiläum, Abschlussfeier...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}), // Update chip display
              ),
            ],
            const SizedBox(height: 24),
            
            // Weekly Schedule Section (Collapsible)
            InkWell(
              onTap: () {
                setState(() {
                  _weeklyScheduleExpanded = !_weeklyScheduleExpanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Wöchentlicher Zeitplan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Icon(
                    _weeklyScheduleExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 28,
                  ),
                ],
              ),
            ),
            if (_weeklyScheduleExpanded) ...[
              const SizedBox(height: 8),
              _buildWeeklyScheduleMatrix(),
            ],
            const SizedBox(height: 24),
            
            // Special Schedules Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sondertermine',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _addSpecialSchedule,
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSpecialSchedulesList(),
            const SizedBox(height: 24),
            
            // Media Items Section
            const Text(
              'Medien & Reihenfolge',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: ReorderableListView.builder(
                itemCount: _items.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = _items.removeAt(oldIndex);
                  _items.insert(newIndex, moved);
                  setState(() {});
                  await _svc.setOrder(
                    widget.playlist.avatarId,
                    widget.playlist.id,
                    _items,
                  );
                },
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final media = _mediaMap[it.mediaId];
                  return ListTile(
                    key: ValueKey(it.id),
                    leading: media == null
                        ? const Icon(Icons.broken_image)
                        : (media.type == AvatarMediaType.video
                            ? const Icon(Icons.videocam)
                            : const Icon(Icons.photo)),
                    title: Text(media?.url.split('/').last ?? it.mediaId),
                    trailing: const Icon(Icons.drag_handle),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyScheduleMatrix() {
    return LayoutBuilder(
      builder: (context, cons) {
        final buttonWidth = ((cons.maxWidth - 32) / 7) - 6;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Stufe: Wochentags-Buttons
            const Text('Wochentage wählen:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final weekday = i + 1;
                final isActive = _weeklySchedule.containsKey(weekday);
                final canSelect = _canSelectWeekday(weekday);
                final isSelected = _selectedWeekday == weekday;
            
                return SizedBox(
                  width: buttonWidth,
                  child: ElevatedButton(
                    onPressed: canSelect || isActive
                        ? () {
                            setState(() {
                              if (_selectedWeekday == weekday) {
                                // Bereits selektiert -> deselektieren
                                _selectedWeekday = null;
                              } else {
                                // Selektieren für Bearbeitung
                                _selectedWeekday = weekday;
                                // Auto-create empty set if not exists
                                _weeklySchedule.putIfAbsent(weekday, () => <TimeSlot>{});
                              }
                            });
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (isSelected || isActive)
                          ? Colors.transparent
                          : Colors.grey.shade800,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade900,
                      disabledForegroundColor: Colors.grey.shade600,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 48),
                    ),
                    child: (isSelected || isActive)
                        ? Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFFE91E63).withValues(alpha: isSelected ? 1.0 : 0.75),
                                  Color(0xFF8AB4F8).withValues(alpha: isSelected ? 1.0 : 0.75),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 12,
                              ),
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _weekdayShort(weekday),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_weekdayShort(weekday)),
                            ),
                          ),
                  ),
                );
              }),
            ),
        
        // 2. Stufe: Zeitfenster für gewählten Tag
        if (_selectedWeekday != null) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              SizedBox(
                width: 200, // Feste Breite für längsten Wochentag ("Zeitfenster für Donnerstag")
                child: Text(
                  'Zeitfenster für ${_weekdayLabel(_selectedWeekday!)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _weeklySchedule.remove(_selectedWeekday);
                    _selectedWeekday = null;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.remove_circle_outline, size: 16),
                label: Text(
                  '${_weekdayShort(_selectedWeekday!)} entfernen',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TimeSlot.values.map((slot) {
                final isActive = _weeklySchedule[_selectedWeekday]?.contains(slot) ?? false;
                final slotWidth = ((cons.maxWidth - 32) / 3) - 6;
                
                return GestureDetector(
                  onTap: () => _toggleTimeSlot(_selectedWeekday!, slot),
                  child: Container(
                    width: slotWidth,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? LinearGradient(
                              colors: [
                                const Color(0xFFE91E63).withValues(alpha: 0.6),
                                const Color(0xFF8AB4F8).withValues(alpha: 0.6),
                              ],
                            )
                          : null,
                      color: isActive ? null : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFFE91E63).withValues(alpha: 0.8)
                            : Colors.grey.shade600,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _timeSlotIcon(slot),
                          style: TextStyle(
                            fontSize: 28,
                            color: isActive ? Colors.white : Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _timeSlotLabel(slot),
                          style: TextStyle(
                            fontSize: 9,
                            color: isActive ? Colors.white : Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Checkbox: Alle Tageszeiten
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    final allSelected = _weeklySchedule[_selectedWeekday]?.length == 6;
                    if (allSelected) {
                      // Alle abwählen
                      _weeklySchedule[_selectedWeekday!]?.clear();
                    } else {
                      // Alle 6 Zeitfenster auswählen
                      _weeklySchedule[_selectedWeekday!] = Set.from(TimeSlot.values);
                    }
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _weeklySchedule[_selectedWeekday]?.length == 6,
                      tristate: true,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            // Alle 6 Zeitfenster auswählen
                            _weeklySchedule[_selectedWeekday!] = Set.from(TimeSlot.values);
                          } else {
                            // Alle abwählen
                            _weeklySchedule[_selectedWeekday!]?.clear();
                          }
                        });
                      },
                    ),
                    const Text('Alle Tageszeiten', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _buildSpecialSchedulesList() {
    if (_specialSchedules.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Keine Sondertermine', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return Column(
      children: _specialSchedules.asMap().entries.map((entry) {
        final index = entry.key;
        final special = entry.value;
        final start = DateTime.fromMillisecondsSinceEpoch(special.startDate);
        final end = DateTime.fromMillisecondsSinceEpoch(special.endDate);
        final slotsText = special.timeSlots.map((s) => _timeSlotLabel(s).split(' ')[0]).join(', ');
        
        return Card(
          child: ListTile(
            leading: const Icon(Icons.event_note, color: Colors.red),
            title: Text('${_fmt(start)} - ${_fmt(end)}'),
            subtitle: Text('Zeitfenster: $slotsText'),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteSpecialSchedule(index),
            ),
            onTap: () => _editSpecialSchedule(index),
          ),
        );
      }).toList(),
    );
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  void _addSpecialSchedule() {
    // Open dialog to add new special schedule
    _showSpecialScheduleDialog(null);
  }

  void _editSpecialSchedule(int index) {
    _showSpecialScheduleDialog(index);
  }

  void _deleteSpecialSchedule(int index) {
    setState(() {
      _specialSchedules.removeAt(index);
    });
  }

  Future<void> _showSpecialScheduleDialog(int? editIndex) async {
    final isEdit = editIndex != null;
    final existing = isEdit ? _specialSchedules[editIndex] : null;
    
    DateTime? startDate = existing != null
        ? DateTime.fromMillisecondsSinceEpoch(existing.startDate)
        : null;
    DateTime? endDate = existing != null
        ? DateTime.fromMillisecondsSinceEpoch(existing.endDate)
        : null;
    Set<TimeSlot> selectedSlots = existing != null
        ? Set.from(existing.timeSlots)
        : <TimeSlot>{};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Sondertermin bearbeiten' : 'Sondertermin hinzufügen'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Start Date
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(startDate != null ? _fmt(startDate!) : 'Startdatum wählen'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => startDate = picked);
                    }
                  },
                ),
                // End Date
                ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(endDate != null ? _fmt(endDate!) : 'Enddatum wählen'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: endDate ?? startDate ?? DateTime.now(),
                      firstDate: startDate ?? DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => endDate = picked);
                    }
                  },
                ),
                const Divider(),
                const Text('Zeitfenster:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Time Slots
                ...TimeSlot.values.map((slot) => CheckboxListTile(
                      title: Text(_timeSlotLabel(slot)),
                      value: selectedSlots.contains(slot),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            selectedSlots.add(slot);
                          } else {
                            selectedSlots.remove(slot);
                          }
                        });
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                if (startDate != null && endDate != null && selectedSlots.isNotEmpty) {
                  final newSpecial = SpecialSchedule(
                    startDate: startDate!.millisecondsSinceEpoch,
                    endDate: endDate!.millisecondsSinceEpoch,
                    timeSlots: selectedSlots.toList(),
                  );
                  
                  setState(() {
                    if (isEdit) {
                      _specialSchedules[editIndex] = newSpecial;
                    } else {
                      _specialSchedules.add(newSpecial);
                    }
                  });
                  Navigator.pop(ctx);
                }
              },
              child: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }
}
