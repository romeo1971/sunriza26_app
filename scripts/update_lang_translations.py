#!/usr/bin/env python3
"""
Utility: Füllt Übersetzungen in assets/lang/*.json auf – NUR über Google Translate.

Funktionsweise
- Quelle ist standardmäßig en.json oder de.json (per --source).
- Für jede andere Sprachdatei werden fehlende Keys ergänzt (oder alle neu mit --rewrite-all).
- Es wird ausschließlich Google Translate verwendet (GOOGLE_TRANSLATE_API_KEY / GOOGLE_API_KEY / GOOGLE_CLOUD_API_KEY).
  Ohne gültigen API-Key wird der Quelltext als Fallback übernommen oder mit --require-google abgebrochen.

Beispiele
  python3 scripts/update_lang_translations.py --source en
  python3 scripts/update_lang_translations.py --source de --overwrite-english
  GOOGLE_TRANSLATE_API_KEY=... python3 scripts/update_lang_translations.py --source en --rewrite-all --require-google

Hinweise
- Das Skript ändert nur JSON in assets/lang/.
- Mit --dry-run werden keine Dateien geschrieben.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Dict, Any, Optional

try:
    # Nur Standardbibliothek verwenden
    from urllib import request, parse
except Exception:  # pragma: no cover
    request = None  # type: ignore
    parse = None  # type: ignore


# Projektwurzel: /sunriza26 (ein Verzeichnis über scripts/)
REPO_ROOT = Path(__file__).resolve().parents[1]
LANG_DIR = REPO_ROOT / "assets" / "lang"

# Falsch angelegte Keys, die ggf. aufräumt werden sollen
BROKEN_KEYS = [
    "ls.regionTitle",
]

# Zuordnung Dateiname -> DeepL Sprachcode
# DeepL wird nicht mehr verwendet (nur Google). Mapping entfernt.

# Mapping Dateiname -> Google Sprachcode
GOOGLE_CODE_BY_FILE = {
    "en": "en",
    "de": "de",
    "fr": "fr",
    "es": "es",
    "it": "it",
    "nl": "nl",
    "pl": "pl",
    "pt": "pt",
    "ru": "ru",
    "ja": "ja",
    "zh-Hans": "zh-CN",
    "zh-Hant": "zh-TW",
    "ko": "ko",
    "tr": "tr",
    "uk": "uk",
    "sv": "sv",
    "cs": "cs",
    "da": "da",
    "fi": "fi",
    "no": "no",
    "hu": "hu",
    "el": "el",
    "ro": "ro",
    "ar": "ar",
    "fa": "fa",
    "hi": "hi",
    "bn": "bn",
    "id": "id",
    "ms": "ms",
    "ta": "ta",
    "te": "te",
    "th": "th",
    "vi": "vi",
    "he": "iw",  # Google akzeptiert teils 'iw' für Hebräisch
    "pa": "pa",
    "mr": "mr",
    "tl": "tl",
}


def load_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def save_json(path: Path, data: Dict[str, Any]) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


# DeepL-Übersetzung entfernt


def _load_env_file_key(keys: list[str]) -> Optional[str]:
    """Versucht, Keys aus .env im Projektroot zu lesen, falls nicht in ENV vorhanden."""
    env_path = REPO_ROOT / ".env"
    if not env_path.exists():
        return None
    try:
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            if k in keys and v:
                return v
    except Exception:
        return None
    return None


def translate_google(text: str, target_code: str, source_code: str | None) -> str:
    # API Key aus ENV oder .env beziehen
    api_key = os.getenv("GOOGLE_TRANSLATE_API_KEY") or _load_env_file_key([
        "GOOGLE_TRANSLATE_API_KEY", "GOOGLE_API_KEY", "GOOGLE_CLOUD_API_KEY"
    ])
    if not api_key or request is None or parse is None:
        return text

    url = f"https://translation.googleapis.com/language/translate/v2?key={api_key}"
    payload = {
        "q": text,
        "target": target_code,
    }
    if source_code:
        payload["source"] = source_code
    data = parse.urlencode(payload).encode("utf-8")
    req = request.Request(url)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with request.urlopen(req, data=data, timeout=20) as resp:  # type: ignore
            if resp.status != 200:
                return text
            res = json.loads(resp.read().decode("utf-8"))
            tr = res.get("data", {}).get("translations", [])
            if isinstance(tr, list) and tr and isinstance(tr[0], dict):
                out = tr[0].get("translatedText")
                if isinstance(out, str) and out.strip():
                    # Google liefert HTML-escaped; einfach zurückgeben
                    return out
    except Exception:
        return text
    return text


def process_language_files(
    source_code: str,
    overwrite_english: bool,
    dry_run: bool,
    only_prefix: str | None,
    rewrite_all: bool = False,
    require_google: bool = False,
) -> None:
    assert LANG_DIR.exists(), f"Lang-Verzeichnis nicht gefunden: {LANG_DIR}"

    source_path = LANG_DIR / f"{source_code}.json"
    source = load_json(source_path)
    if not source:
        raise SystemExit(f"Quelle {source_path} ist leer/nicht vorhanden.")

    # optional: nur Keys mit Prefix
    if only_prefix:
        source = {k: v for k, v in source.items() if str(k).startswith(only_prefix)}

    changed_total = 0
    # Google API Key auflösen
    google_key = os.getenv("GOOGLE_TRANSLATE_API_KEY") or _load_env_file_key([
        "GOOGLE_TRANSLATE_API_KEY", "GOOGLE_API_KEY", "GOOGLE_CLOUD_API_KEY"
    ])
    if require_google and not google_key:
        raise SystemExit("Google Translate API Key fehlt (GOOGLE_TRANSLATE_API_KEY / GOOGLE_API_KEY / GOOGLE_CLOUD_API_KEY)")

    for path in sorted(LANG_DIR.glob("*.json")):
        code = path.stem
        if code == source_code:
            continue
        target = load_json(path)

        # Aufräumen falscher Keys
        for bk in BROKEN_KEYS:
            if bk in target:
                del target[bk]

        # Welche Keys bearbeiten?
        if rewrite_all:
            missing = list(source.keys())
        else:
            # Nur fehlende Keys
            missing = [k for k in source.keys() if k not in target]

        # Optional vorhandene englische Fallbacks überschreiben
        if overwrite_english and code != "en" and not rewrite_all:
            for k in list(target.keys()):
                if k in source and target.get(k) == source.get(k):  # identisch zum Source-Text
                    if k not in missing:
                        missing.append(k)  # neu übersetzen

        if not missing:
            continue

        # Übersetzen / Fallback
        tgt_code_google = GOOGLE_CODE_BY_FILE.get(code)
        src_code_google = GOOGLE_CODE_BY_FILE.get(source_code)
        for k in missing:
            raw = str(source[k])
            translated = raw
            if google_key and tgt_code_google:
                translated = translate_google(raw, tgt_code_google, src_code_google)
            target[k] = translated

        changed_total += len(missing)
        if not dry_run:
            save_json(path, target)

    print(f"Done. Ergänzte Einträge: {changed_total}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Fehlende Übersetzungen auffüllen")
    parser.add_argument("--source", choices=[p.stem for p in LANG_DIR.glob("*.json")], default="en")
    parser.add_argument("--overwrite-english", action="store_true", help="Existierende Werte erneut übersetzen, wenn sie identisch zur Quelle sind")
    parser.add_argument("--dry-run", action="store_true", help="Nur anzeigen, nicht schreiben")
    parser.add_argument("--only-prefix", type=str, default=None, help="Nur Keys mit diesem Prefix verarbeiten, z.B. 'avatars.details.'")
    parser.add_argument("--rewrite-all", action="store_true", help="Alle Keys in Nicht-Quellsprachen neu übersetzen (nicht nur fehlende)")
    parser.add_argument("--require-google", action="store_true", help="Abbrechen, wenn kein Google Translate API Key vorhanden ist")
    args = parser.parse_args()

    process_language_files(
        source_code=args.source,
        overwrite_english=args.overwrite_english,
        dry_run=args.dry_run,
        only_prefix=args.only_prefix,
        rewrite_all=args.rewrite_all,
        require_google=args.require_google,
    )


if __name__ == "__main__":
    main()


