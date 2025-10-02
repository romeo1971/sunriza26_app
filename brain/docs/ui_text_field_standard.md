# UI Standard: TextField Design

## Komponente: `CustomTextField`

### Problem
Inconsistente TextField-Designs in der App:
- Unterschiedliche Border-Styles
- Verschiedene Fokus-Farben
- Inkonsistente Abstände und Radien
- Labels teilweise außerhalb, teilweise integriert

### Lösung: Wiederverwendbares `CustomTextField` Widget

**Pfad:** `lib/widgets/custom_text_field.dart`

### Design-Entscheidungen

#### 1. **Label integriert im Border** ✅
```dart
InputDecoration(
  labelText: 'Stadt oder PLZ',  // ← Schwebt im Border
  hintText: '85737, Ismaning',  // ← Placeholder im Feld
)
```

**Vorteile:**
- ✅ **Platzsparend** - kein extra Raum für Label nötig
- ✅ **Material Design** - Standard-Verhalten
- ✅ **Sauber** - Label bewegt sich beim Fokus nach oben

#### 2. **Grüner Fokus-Border**
```dart
focusedBorder: OutlineInputBorder(
  borderSide: BorderSide(
    color: AppColors.accentGreenDark,  // ← Grün = aktiv
    width: 2,
  ),
)
```

#### 3. **Abgerundete Ecken (12px)**
```dart
borderRadius: BorderRadius.circular(12)
```

#### 4. **Leichte Hintergrund-Füllung**
```dart
filled: true,
fillColor: Colors.white.withValues(alpha: 0.05)
```

## Verwendung

### Basic TextField
```dart
import '../widgets/custom_text_field.dart';

CustomTextField(
  controller: _nameController,
  label: 'Vorname',
  hint: 'Max',
)
```

### TextField mit Validierung
```dart
CustomTextField(
  controller: _emailController,
  label: 'E-Mail',
  hint: 'max@example.com',
  keyboardType: TextInputType.emailAddress,
  validator: (value) {
    if (value == null || value.isEmpty) {
      return 'Bitte E-Mail eingeben';
    }
    if (!value.contains('@')) {
      return 'Ungültige E-Mail';
    }
    return null;
  },
)
```

### Multiline TextField
```dart
CustomTextField(
  controller: _descriptionController,
  label: 'Beschreibung',
  hint: 'Erzähle etwas über...',
  maxLines: 5,
)
```

### Password Field
```dart
CustomTextField(
  controller: _passwordController,
  label: 'Passwort',
  obscureText: true,
  maxLength: 50,
)
```

### Date Field (readonly mit Kalender)
```dart
CustomDateField(
  controller: _birthDateController,
  label: 'Geburtsdatum',
  hint: 'TT.MM.JJJJ',
  onTap: () => _selectDate(),
)
```

### ReadOnly Field (z.B. für berechnete Werte)
```dart
CustomTextField(
  controller: _calculatedController,
  label: 'Berechnet',
  readOnly: true,
)
```

## Migration-Checkliste

### Screens zu migrieren:
- [ ] **avatar_details_screen.dart**
  - Vorname, Nachname, Spitzname
  - Stadt/PLZ, Land (bereits migriert ✅)
  - Geburtsdatum, Sterbedatum
  - Begrüßungstext
  - Freitext-Area

- [ ] **avatar_creation_screen.dart**
  - Vorname, Nachname, Spitzname
  - Geburtsdatum, Sterbedatum

- [ ] **user_profile_screen.dart**
  - Alle Benutzer-Felder

- [ ] **playlist_edit_screen.dart**
  - Playlist-Name
  - Beschreibung

- [ ] **avatar_chat_screen.dart**
  - Chat-Eingabefeld (falls anpassbar)

- [ ] **login/signup Screens**
  - E-Mail, Passwort Felder

### Suchmuster für alte Felder:
```bash
# Finde alle TextField ohne CustomTextField
grep -r "TextField(" lib/screens/ | grep -v "CustomTextField"

# Finde alle TextFormField
grep -r "TextFormField(" lib/screens/
```

## Anti-Patterns (NICHT tun!)

❌ **Label außerhalb des Feldes:**
```dart
Column(
  children: [
    Text('Name'),  // ← Braucht extra Platz
    TextField(...),
  ],
)
```

❌ **Inkonsistente Border-Farben:**
```dart
focusedBorder: BorderSide(color: Colors.blue)  // ← Immer grün nutzen!
```

❌ **Kein BorderRadius:**
```dart
border: OutlineInputBorder()  // ← Immer 12px Radius!
```

❌ **Direkt TextField statt CustomTextField:**
```dart
TextField(...)  // ← Nutze CustomTextField für Konsistenz!
```

## Vorteile des Standards

1. ✅ **Konsistenz** - Alle Felder sehen gleich aus
2. ✅ **Wartbarkeit** - Änderungen an EINER Stelle
3. ✅ **Platzsparend** - Label im Border spart Vertikal-Raum
4. ✅ **Accessibility** - Material Design = Screen Reader freundlich
5. ✅ **Performance** - Weniger Widget-Rebuilds
6. ✅ **UX** - Nutzer lernen Interaktion einmal

## Beispiel: Vorher/Nachher

### VORHER (inkonsistent):
```dart
// Verschiedene Styles in verschiedenen Screens
TextField(
  decoration: InputDecoration(
    border: InputBorder.none,  // ← Kein Border
  ),
)

TextField(
  decoration: InputDecoration(
    border: OutlineInputBorder(),  // ← Eckig
    labelText: 'Name',
  ),
)

Column(
  children: [
    Text('Name'),  // ← Label extra
    TextField(),
  ],
)
```

### NACHHER (konsistent):
```dart
// Überall gleich
CustomTextField(
  controller: _controller,
  label: 'Name',
  hint: 'Max Mustermann',
)
```

## Theme Integration

Das `CustomTextField` nutzt automatisch:
- `AppColors.accentGreenDark` für Fokus
- `Colors.white` für Text (Dark Theme)
- `Colors.white70` für Label
- `Colors.white38` für Hint

**Dokumentiert:** Oktober 2025 | Sunriza26 App
**Standard seit:** Navigation-Architektur Update

