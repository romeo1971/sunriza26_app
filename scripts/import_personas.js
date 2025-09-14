#!/usr/bin/env node
/*
  Importiert Persona-Texte als globale Pinecone-Dokumente via Cloud Function processDocument.
  - Chunkgröße ~700 Zeichen, Overlap 120 Zeichen
  - userId = 'global'
  - tags enthalten persona & scope=global_base
*/
const fs = require('fs');
const path = require('path');
const https = require('https');

const CF_URL = 'https://us-central1-sunriza26.cloudfunctions.net/processDocument';
const PERSONA_DIR = path.join(__dirname, '..', 'assets', 'personas');

function chunkText(text, size = 700, overlap = 120) {
  const chunks = [];
  let i = 0;
  for (let start = 0; start < text.length; start += (size - overlap)) {
    const end = Math.min(text.length, start + size);
    const slice = text.slice(start, end).trim();
    if (slice.length > 0) {
      chunks.push({ index: i++, text: slice });
    }
    if (end >= text.length) break;
  }
  return chunks;
}

function postJson(url, body) {
  return new Promise((resolve, reject) => {
    const data = Buffer.from(JSON.stringify(body));
    const u = new URL(url);
    const req = https.request({
      method: 'POST',
      hostname: u.hostname,
      path: u.pathname + u.search,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length,
      },
    }, (res) => {
      const bufs = [];
      res.on('data', (c) => bufs.push(c));
      res.on('end', () => {
        const txt = Buffer.concat(bufs).toString('utf8');
        if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
          resolve({ status: res.statusCode, body: txt });
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${txt}`));
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function personaMetaFromFilename(file) {
  const base = path.basename(file).toLowerCase();
  if (base.includes('psych_base')) {
    return { persona: ['psych_base','beziehung','trauer','suizid','empathie'], tags: ['rolle','haltung','empathie','safety'] };
  }
  if (base.includes('fitness')) {
    return { persona: ['fitness', 'coaching'], tags: ['fitness','motivation','coaching'] };
  }
  if (base.includes('sex') || base.includes('erotik') || base.includes('flirt')) {
    return { persona: ['sex','flirt','erotik'], tags: ['sex','flirt','erotik','kink','konsens'] };
  }
  return { persona: ['general'], tags: [] };
}

async function main() {
  if (!fs.existsSync(PERSONA_DIR)) {
    console.error('Persona-Verzeichnis fehlt:', PERSONA_DIR);
    process.exit(1);
  }
  const files = fs.readdirSync(PERSONA_DIR)
    .filter(f => f.endsWith('.txt'))
    .map(f => path.join(PERSONA_DIR, f));
  if (files.length === 0) {
    console.error('Keine Persona-Texte gefunden.');
    process.exit(1);
  }
  const uploaded = [];
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    const chunks = chunkText(text, 750, 120); // ~750 Zeichen
    const meta = personaMetaFromFilename(file);
    let idx = 0;
    for (const ch of chunks) {
      const documentId = `${path.basename(file)}#${idx}`;
      const payload = {
        userId: 'global',
        documentId,
        content: ch.text,
        metadata: {
          type: 'text',
          userId: 'global',
          uploadDate: new Date().toISOString(),
          originalFileName: path.basename(file),
          contentType: 'text/plain',
          size: ch.text.length,
          description: ch.text.slice(0, 160),
          tags: [...meta.tags, ...meta.persona.map(p => `persona:${p}`), 'scope:global_base']
        }
      };
      await postJson(CF_URL, payload);
      uploaded.push(documentId);
      idx += 1;
    }
    console.log(`Imported ${idx} chunks from ${path.basename(file)}`);
  }
  console.log('DONE:', uploaded.length, 'chunks total.');
}

main().catch((e) => {
  console.error('Import-Fehler:', e.message);
  process.exit(1);
});
