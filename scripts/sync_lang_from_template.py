#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANG_DIR = ROOT / 'assets' / 'lang'
TEMPLATE = LANG_DIR / 'lang.template.json'

def load_json(p: Path):
    with p.open('r', encoding='utf-8') as f:
        return json.load(f)

def save_json(p: Path, data: dict):
    # stable key order for readability
    with p.open('w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write('\n')

def main():
    template = load_json(TEMPLATE)
    files = [p for p in LANG_DIR.glob('*.json') if p.name != 'lang.template.json']
    updated = []
    for fp in files:
        data = load_json(fp)
        before = set(data.keys())
        for k, v in template.items():
            if k not in data:
                data[k] = v
        if set(data.keys()) != before:
            save_json(fp, data)
            updated.append(fp.name)
    print('updated:', ', '.join(updated))

if __name__ == '__main__':
    main()


