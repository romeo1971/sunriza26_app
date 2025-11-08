import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_theme.dart';
import '../custom_text_field.dart';
import 'expansion_tile_base.dart';

class SocialMediaAccount {
  final String id;
  final String providerName;
  final String url;
  final String login;
  final String passwordEnc; // AES verschlüsselt (iv:cipher b64)
  final bool connected;

  SocialMediaAccount({
    required this.id,
    required this.providerName,
    required this.url,
    required this.login,
    required this.passwordEnc,
    required this.connected,
  });

  Map<String, dynamic> toMap() => {
        'providerName': providerName,
        'url': url,
        'login': login,
        'passwordEnc': passwordEnc,
        'connected': connected,
      };

  static SocialMediaAccount fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return SocialMediaAccount(
      id: d.id,
      providerName: (m['providerName'] as String?) ?? detectProviderFromUrl((m['url'] as String?) ?? ''),
      url: (m['url'] as String?) ?? '',
      login: (m['login'] as String?) ?? '',
      passwordEnc: (m['passwordEnc'] as String?) ?? '',
      connected: (m['connected'] as bool?) ?? false,
    );
  }
}

/// Provider aus URL erkennen (Top-Level, für Model und UI nutzbar)
String detectProviderFromUrl(String url) {
  final u = url.toLowerCase();
  if (u.contains('instagram.com')) return 'Instagram';
  if (u.contains('facebook.com')) return 'Facebook';
  if (u.contains('tiktok.com')) return 'TikTok';
  if (u.contains('x.com') || u.contains('twitter.com')) return 'X';
  if (u.contains('linkedin.com')) return 'LinkedIn';
  return 'Website';
}

class SocialMediaExpansionTile extends StatefulWidget {
  final String avatarId;
  const SocialMediaExpansionTile({super.key, required this.avatarId});

  @override
  State<SocialMediaExpansionTile> createState() => _SocialMediaExpansionTileState();
}

class _SocialMediaExpansionTileState extends State<SocialMediaExpansionTile> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  List<SocialMediaAccount> _items = <SocialMediaAccount>[];
  String? _editingId; // null = kein Edit, 'new' = neuer Eintrag
  final _urlCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _showPassword = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _loginCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> _col() {
    return _fs.collection('avatars').doc(widget.avatarId).collection('social_accounts');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final qs = await _col().get();
      _items = qs.docs.map(SocialMediaAccount.fromDoc).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save({required bool isNew, String? id}) async {
    final url = _urlCtrl.text.trim();
    final login = _loginCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (url.isEmpty) {
      _toast('URL erforderlich');
      return;
    }
    final provider = _detectProvider(url);
    final encPwd = await _encrypt(pwd);
    try {
      if (isNew) {
        await _col().add({
          'providerName': provider,
          'url': url,
          'login': login,
          'passwordEnc': encPwd,
          'connected': false,
        });
      } else if (id != null) {
        await _col().doc(id).set({
          'providerName': provider,
          'url': url,
          'login': login,
          'passwordEnc': encPwd,
        }, SetOptions(merge: true));
      }
      await _load();
      _editingId = null;
      _clearCtrls();
      _toast('Gespeichert');
    } catch (e) {
      _toast('Fehler: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Löschen bestätigen', style: TextStyle(color: Colors.white)),
        content: const Text('Eintrag wirklich löschen?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _col().doc(id).delete();
      await _load();
      _toast('Gelöscht');
    } catch (e) {
      _toast('Fehler: $e');
    }
    if (mounted) setState(() {});
  }

  void _startEdit(SocialMediaAccount? m) {
    _editingId = m?.id ?? 'new';
    _urlCtrl.text = m?.url ?? '';
    _loginCtrl.text = m?.login ?? '';
    _pwdCtrl.text = ''; // Sicherheit: nie automatisch füllen
    _showPassword = false;
    setState(() {});
  }

  void _clearCtrls() {
    _urlCtrl.clear();
    _loginCtrl.clear();
    _pwdCtrl.clear();
    _showPassword = false;
  }

  Future<void> _toggleConnect(SocialMediaAccount m, bool next) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      if (next) {
        // Verbinden → nutze gespeicherte Daten
        final ok = await _fakeConnect(m);
        if (!ok) {
          _toast('Verbindung fehlgeschlagen');
          return;
        }
      }
      await _col().doc(m.id).set({'connected': next}, SetOptions(merge: true));
      await _load();
      _toast(next ? 'Verbunden' : 'Getrennt');
    } catch (e) {
      _toast('Fehler: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<bool> _fakeConnect(SocialMediaAccount m) async {
    // Platzhalter: Hier echte Provider-Auth/Fetch integrieren
    await Future.delayed(const Duration(milliseconds: 600));
    return m.url.isNotEmpty; // minimal
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.black87),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Social Media', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'Neu',
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _startEdit(null),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_editingId != null)
        _buildEditor()
      else if (_items.isEmpty)
        const Text('Keine Einträge', style: TextStyle(color: Colors.white60))
      else
        ..._items.map(_buildRow),
    ];

    return BaseExpansionTile(
      title: 'Social Media',
      emoji: '🌐',
      initiallyExpanded: false,
      children: children,
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTextField(
          label: 'URL',
          controller: _urlCtrl,
          hintText: 'z. B. https://www.instagram.com/...',
          prefixIcon: const Icon(Icons.link, color: Colors.white70, size: 18),
        ),
        const SizedBox(height: 8),
        CustomTextField(
          label: 'Login (Username/Email)',
          controller: _loginCtrl,
          prefixIcon: const Icon(Icons.person_outline, color: Colors.white70, size: 18),
        ),
        const SizedBox(height: 8),
        CustomTextField(
          label: 'Passwort',
          controller: _pwdCtrl,
          obscureText: !_showPassword,
          prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70, size: 18),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showPassword = !_showPassword),
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white70, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => _save(isNew: _editingId == 'new', id: _editingId == 'new' ? null : _editingId),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              child: const Text('Speichern'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _editingId = null;
                _clearCtrls();
                setState(() {});
              },
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(SocialMediaAccount m) {
    final icon = _iconForProvider(m.providerName);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.providerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(m.login.isNotEmpty ? m.login : '(kein Login)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Mini Toggle: Verbinden/Trennen
          InkWell(
            onTap: _connecting ? null : () => _toggleConnect(m, !m.connected),
            child: _miniToggle(m.connected),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Bearbeiten',
            icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
            onPressed: () => _startEdit(m),
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
            onPressed: () => _delete(m.id),
          ),
        ],
      ),
    );
  }

  Widget _miniToggle(bool value) {
    return Container(
      width: 48,
      height: 28,
      decoration: BoxDecoration(
        color: value ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: value
                ? const LinearGradient(
                    colors: [AppColors.magenta, AppColors.lightBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: value ? null : Colors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  static String _detectProvider(String url) {
    final u = url.toLowerCase();
    if (u.contains('instagram.com')) return 'Instagram';
    if (u.contains('facebook.com')) return 'Facebook';
    if (u.contains('tiktok.com')) return 'TikTok';
    if (u.contains('x.com') || u.contains('twitter.com')) return 'X';
    if (u.contains('linkedin.com')) return 'LinkedIn';
    return 'Website';
  }

  Widget _iconForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'instagram':
        return const FaIcon(FontAwesomeIcons.instagram, color: Color(0xFFE4405F), size: 22);
      case 'facebook':
        return const FaIcon(FontAwesomeIcons.facebook, color: Color(0xFF1877F2), size: 22);
      case 'x':
        return const FaIcon(FontAwesomeIcons.xTwitter, color: Colors.white, size: 22);
      case 'tiktok':
        return const FaIcon(FontAwesomeIcons.tiktok, color: Colors.white, size: 22);
      case 'linkedin':
        return const FaIcon(FontAwesomeIcons.linkedin, color: Color(0xFF0A66C2), size: 22);
      default:
        return const FaIcon(FontAwesomeIcons.globe, color: Colors.white, size: 22);
    }
  }

  Future<String> _encrypt(String plain) async {
    final uid = _auth.currentUser?.uid ?? 'anon';
    final keyBytes = Uint8List.fromList(_deriveKey(uid));
    final key = enc.Key(keyBytes);
    // AES-CBC: 16 Byte IV
    final iv16 = enc.IV(Uint8List.fromList(_randomBytes(16)));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plain, iv: iv16);
    // Speichere iv:cipher als base64: iv|cipher
    return base64Encode(iv16.bytes) + ':' + encrypted.base64;
  }

  Future<String> _decrypt(String data) async {
    try {
      final parts = data.split(':');
      if (parts.length != 2) return '';
      final ivBytes = base64Decode(parts[0]);
      final cipherB64 = parts[1];
      final uid = _auth.currentUser?.uid ?? 'anon';
      final key = enc.Key(Uint8List.fromList(_deriveKey(uid)));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt(enc.Encrypted.fromBase64(cipherB64), iv: enc.IV(ivBytes));
      return decrypted;
    } catch (_) {
      return '';
    }
  }

  List<int> _deriveKey(String uid) {
    // Simple Ableitung: uid Hash zu 32 Bytes auffüllen/trimmen (clientseitig; ausreichend für obfuskierten Speicher)
    final b = utf8.encode(uid);
    final out = List<int>.filled(32, 0);
    for (int i = 0; i < 32; i++) {
      out[i] = b[i % b.length] ^ (i * 31);
    }
    return out;
  }

  List<int> _randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }
}


