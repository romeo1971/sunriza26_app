import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/legal_page.dart';
import '../services/legal_service.dart';
import '../widgets/app_drawer.dart';

class LegalPageScreen extends StatefulWidget {
  final String type; // 'terms', 'imprint', 'privacy'

  const LegalPageScreen({super.key, required this.type});

  @override
  State<LegalPageScreen> createState() => _LegalPageScreenState();
}

class _LegalPageScreenState extends State<LegalPageScreen> {
  final LegalService _legalService = LegalService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  LegalPage? _legalPage;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isAdmin = false;
  bool _isHtml = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final [page, isAdmin] = await Future.wait([
        _legalService.getLegalPage(widget.type),
        _legalService.isAdmin(),
      ]);

      setState(() {
        _legalPage = page as LegalPage?;
        _isAdmin = isAdmin as bool;
        if (_legalPage != null) {
          _titleController.text = _legalPage!.title;
          _contentController.text = _legalPage!.content;
          _isHtml = _legalPage!.isHtml;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty ||
        _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titel und Inhalt sind erforderlich')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final page = LegalPage(
        id: widget.type,
        type: widget.type,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        isHtml: _isHtml,
        createdAt: _legalPage?.createdAt ?? now,
        updatedAt: now,
      );

      final success = await _legalService.saveLegalPage(page);

      if (success) {
        setState(() {
          _legalPage = page;
          _isEditing = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erfolgreich gespeichert')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fehler beim Speichern')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'html', 'htm'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        final content = String.fromCharCodes(file.bytes!);

        setState(() {
          _contentController.text = content;
          _isHtml =
              file.extension?.toLowerCase() == 'html' ||
              file.extension?.toLowerCase() == 'htm';
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Datei "${file.name}" geladen')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fehler beim Dateienupload: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: Text(_getTitle()),
        foregroundColor: Colors.white,
        actions: [
          if (_isAdmin && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: _uploadFile,
            ),
            IconButton(icon: const Icon(Icons.save), onPressed: _save),
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  if (_legalPage != null) {
                    _titleController.text = _legalPage!.title;
                    _contentController.text = _legalPage!.content;
                    _isHtml = _legalPage!.isHtml;
                  }
                });
              },
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isEditing) {
      return _buildEditMode();
    } else {
      return _buildViewMode();
    }
  }

  Widget _buildViewMode() {
    if (_legalPage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'Keine Inhalte verfügbar',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            if (_isAdmin) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() => _isEditing = true),
                child: const Text('Inhalte erstellen'),
              ),
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _legalPage!.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _legalPage!.isHtml
                ? SelectableText(
                    _legalPage!.content,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      height: 1.5,
                    ),
                  )
                : SelectableText(
                    _legalPage!.content,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      height: 1.5,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            'Letzte Aktualisierung: ${_formatDate(_legalPage!.updatedAt)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildEditMode() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Titel',
              labelStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade600),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade600),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.deepPurple),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _isHtml,
                onChanged: (value) => setState(() => _isHtml = value ?? false),
                activeColor: Colors.deepPurple,
              ),
              const Text('HTML-Format', style: TextStyle(color: Colors.white)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _uploadFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Datei hochladen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _contentController,
            maxLines: 20,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Inhalt',
              labelStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade600),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade600),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.deepPurple),
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Speichern'),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isEditing = false;
                    if (_legalPage != null) {
                      _titleController.text = _legalPage!.title;
                      _contentController.text = _legalPage!.content;
                      _isHtml = _legalPage!.isHtml;
                    }
                  });
                },
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getTitle() {
    switch (widget.type) {
      case 'terms':
        return 'AGB';
      case 'imprint':
        return 'Impressum';
      case 'privacy':
        return 'Datenschutz';
      default:
        return 'Rechtliche Informationen';
    }
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}.${date.month}.${date.year}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}
