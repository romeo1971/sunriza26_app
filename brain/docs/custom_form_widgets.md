# Custom Form Widgets - Corporate Identity

## Übersicht

Einheitliche, wiederverwendbare Form-Widgets mit konsistentem Styling für die gesamte App.

## Widgets

### 1. CustomTextField
**Verwendung:** Einzeilige Texteingaben

**Features:**
- Label erscheint nur bei Fokus/Wert (FloatingLabelBehavior.auto)
- Placeholder sichtbar wenn leer
- Weiße Border (Colors.white30), kein Grün
- Transparenter Hintergrund (filled: false)
- contentPadding: horizontal: 12, vertical: 16

**Beispiel:**
```dart
CustomTextField(
  label: 'Vorname',
  controller: _firstNameController,
  onChanged: (value) => setState(() {}),
)
```

### 2. CustomTextArea
**Verwendung:** Mehrzeilige Texteingaben

**Features:**
- Identisches Styling wie CustomTextField
- minLines: 3, maxLines: 8 (anpassbar)

**Beispiel:**
```dart
CustomTextArea(
  label: 'Begrüßungstext',
  controller: _greetingController,
  minLines: 4,
  maxLines: 8,
)
```

### 3. CustomDateField
**Verwendung:** Datumseingaben

**Features:**
- Label erscheint nur bei Fokus/Wert
- Öffnet DatePicker beim Tap
- Kalender-Icon rechts (grün wenn Datum ausgewählt)
- contentPadding: horizontal: 12, vertical: 16
- Identisches Styling wie CustomTextField

**Beispiel:**
```dart
CustomDateField(
  label: 'Geburtsdatum',
  selectedDate: _birthDate,
  onDateSelected: (date) => setState(() => _birthDate = date),
)
```

### 4. CustomDropdown
**Verwendung:** Select/Dropdown Felder

**Features:**
- Label erscheint nur bei Fokus/Wert
- contentPadding: horizontal: 12, vertical: 4 (reduziert für DropdownButton)
- Identisches Styling wie CustomTextField
- **WICHTIG:** Vertical Padding reduziert, da DropdownButton selbst Höhe mitbringt

**Beispiel:**
```dart
CustomDropdown<String>(
  label: 'Rolle',
  value: _selectedRole,
  items: roles.map((role) => DropdownMenuItem(
    value: role,
    child: Text(role),
  )).toList(),
  onChanged: (value) => setState(() => _selectedRole = value),
)
```

## Styling-Regeln (Corporate Identity)

### Farben
- **Label:** `Colors.white70`
- **Hint/Placeholder:** `Colors.white54`
- **Input Text:** `Colors.white`
- **Border (immer):** `Colors.white30`
- **Border (disabled):** `Colors.white12`
- **Hintergrund:** Transparent (`filled: false`)

### Typography
- **Label:** `fontSize: 16`, `fontWeight: normal`
- **Input:** `fontSize: 16`

### Layout
- **Border Radius:** `12px`
- **floatingLabelBehavior:** `FloatingLabelBehavior.auto` (Label nur bei Fokus/Wert)
- **Background:** Transparent (`filled: false`)
- **contentPadding:**
  - TextField/DateField: `horizontal: 12, vertical: 16`
  - Dropdown: `horizontal: 12, vertical: 4` (reduziert wegen DropdownButton-Höhe)

### Verhalten
- **Leer:** Nur Placeholder sichtbar
- **Fokus:** Label erscheint oben links
- **Mit Wert:** Label bleibt oben links sichtbar

## Höhen-Konsistenz

Alle Felder haben die **gleiche visuelle Höhe**:
- **TextField:** `vertical: 16` → Standard-Höhe
- **DateField:** `vertical: 16` → Gleiche Höhe wie TextField
- **Dropdown:** `vertical: 4` → Reduziert, da DropdownButton zusätzliche Höhe hat

**Wichtig:** Dropdown benötigt reduziertes Padding, da der `DropdownButton` selbst bereits Höhe mitbringt und sonst zu groß wird.

## Migration

Alle bisherigen Form-Elemente wurden ersetzt:
- `TextField` → `CustomTextField`
- Mehrzeilige `TextField` → `CustomTextArea`
- Datumsfelder → `CustomDateField`
- `DropdownButton`/`DropdownButtonFormField` → `CustomDropdown`
- Suchfelder → `CustomTextField` (mit `prefixIcon: Icon(Icons.search)`)

## Implementierte Screens
- ✅ avatar_details_screen.dart
- ✅ user_profile_screen.dart
- ✅ playlist_edit_screen.dart
- ✅ playlist_list_screen.dart
- ✅ avatar_list_screen.dart
- ✅ media_gallery_screen.dart

## Dateien

**Widgets:**
- `/lib/widgets/custom_text_field.dart`
- `/lib/widgets/custom_date_field.dart`
- `/lib/widgets/custom_dropdown.dart`

**Dokumentation:**
- `/brain/docs/custom_form_widgets.md`
