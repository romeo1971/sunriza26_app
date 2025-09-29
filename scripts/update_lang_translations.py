#!/usr/bin/env python3
"""
Utility: Füllt fehlende Übersetzungen in assets/lang/*.json auf.

Funktionsweise
- Quelle ist standardmäßig en.json oder de.json (per --source).
- Für jede andere Sprachdatei werden fehlende Keys ergänzt.
- Wenn eine DeepL-API verfügbar ist (DEEPL_API_KEY Umgebungsvariable),
  werden fehlende Werte automatisch übersetzt. Andernfalls wird der
  Quelltext als Fallback übernommen.

Beispiele
  python3 scripts/update_lang_translations.py --source en
  python3 scripts/update_lang_translations.py --source de --overwrite-english
  DEEPL_API_KEY=... python3 scripts/update_lang_translations.py --source en

Hinweise
- Das Skript ändert nur JSON in assets/lang/.
- Mit --dry-run werden keine Dateien geschrieben.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Dict, Any

try:
    # Nur Standardbibliothek verwenden
    from urllib import request, parse
except Exception:  # pragma: no cover
    request = None  # type: ignore
    parse = None  # type: ignore


REPO_ROOT = Path(__file__).resolve().parents[2]
LANG_DIR = REPO_ROOT / "assets" / "lang"

# Falsch angelegte Keys, die ggf. aufräumt werden sollen
BROKEN_KEYS = [
    "ls.regionTitle",
]

# Zuordnung Dateiname -> DeepL Sprachcode
DEEPL_CODE_BY_FILE = {
    # Volle Unterstützung (DeepL Stand 2024/2025; kann sich ändern)
    "en": "EN",
    "de": "DE",
    "fr": "FR",
    "es": "ES",
    "it": "IT",
    "nl": "NL",
    "pl": "PL",
    "pt": "PT-PT",  # oder "PT-BR" bei Bedarf
    "ru": "RU",
    "ja": "JA",
    "zh-Hans": "ZH",
    "zh-Hant": "ZH",
    "ko": "KO",
    "tr": "TR",
    "uk": "UK",
}


def load_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def save_json(path: Path, data: Dict[str, Any]) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def translate_deepl(text: str, target_code: str, source_code: str | None) -> str:
    api_key = os.getenv("DEEPL_API_KEY")
    if not api_key or request is None or parse is None:
        return text  # Fallback: unverändert

    url = "https://api-free.deepl.com/v2/translate"
    payload = {
        "text": text,
        "target_lang": target_code,
    }
    if source_code:
        payload["source_lang"] = source_code

    data = parse.urlencode(payload).encode("utf-8")
    req = request.Request(url)
    req.add_header("Authorization", f"DeepL-Auth-Key {api_key}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")

    try:
        with request.urlopen(req, data=data, timeout=20) as resp:  # type: ignore
            if resp.status != 200:
                return text
            res = json.loads(resp.read().decode("utf-8"))
            tr = res.get("translations")
            if isinstance(tr, list) and tr and isinstance(tr[0], dict):
                out = tr[0].get("text")
                if isinstance(out, str) and out.strip():
                    return out
    except Exception:
        return text
    return text


def process_language_files(
    source_code: str,
    overwrite_english: bool,
    dry_run: bool,
    only_prefix: str | None,
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
    for path in sorted(LANG_DIR.glob("*.json")):
        code = path.stem
        if code == source_code:
            continue
        target = load_json(path)

        # Aufräumen falscher Keys
        for bk in BROKEN_KEYS:
            if bk in target:
                del target[bk]

        # Welche Keys fehlen?
        missing = [k for k in source.keys() if k not in target]

        # Optional vorhandene englische Fallbacks überschreiben
        if overwrite_english and code != "en":
            for k, v in list(target.items()):
                if k in source and target[k] == source[k]:  # identisch zum Source-Text
                    missing.append(k)  # neu übersetzen

        if not missing:
            continue

        # Übersetzen / Fallback
        tgt_code = DEEPL_CODE_BY_FILE.get(code)
        src_code = DEEPL_CODE_BY_FILE.get(source_code)
        for k in missing:
            raw = str(source[k])
            translated = translate_deepl(raw, tgt_code, src_code) if tgt_code else raw
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
    args = parser.parse_args()

    process_language_files(
        source_code=args.source,
        overwrite_english=args.overwrite_english,
        dry_run=args.dry_run,
        only_prefix=args.only_prefix,
    )


if __name__ == "__main__":
    main()


