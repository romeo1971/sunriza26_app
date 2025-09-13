const fs = require('fs');
const path = require('path');

const projectRoot = process.cwd();
const envPath = path.join(projectRoot, '.env');
const localSaPath = path.join(projectRoot, 'service-account-key.json');
const downloadsSaPath = path.join(process.env.HOME || '', 'Downloads', 'sunriza26-firebase-adminsdk-fbsvc-063c3e78ae.json');

const saPath = fs.existsSync(localSaPath) ? localSaPath : downloadsSaPath;
if (!fs.existsSync(saPath)) {
  console.error('Service-Account JSON nicht gefunden:', saPath);
  process.exit(1);
}

const j = JSON.parse(fs.readFileSync(saPath, 'utf8'));
let env = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';

function escapeRegex(text) {
  return text.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
}

function setKV(key, value) {
  if (typeof value === 'undefined' || value === null) {
    value = '';
  }
  if (typeof value === 'string') {
    const needsQuotes = !/^[A-Za-z0-9_:\/\-\.]+$/.test(value);
    if (needsQuotes && !value.startsWith('"')) {
      value = JSON.stringify(value);
    }
  }
  const re = new RegExp('^' + escapeRegex(key) + '=.*$', 'm');
  if (env.match(re)) {
    env = env.replace(re, key + '=' + value);
  } else {
    env += (env.endsWith('\n') ? '' : '\n') + key + '=' + value + '\n';
  }
}

setKV('FIREBASE_PROJECT_ID', j.project_id);
setKV('FIREBASE_PRIVATE_KEY_ID', j.private_key_id);
// Private Key als JSON-String schreiben (enthält \n Sequenzen)
setKV('FIREBASE_PRIVATE_KEY', JSON.stringify(j.private_key));
setKV('FIREBASE_CLIENT_EMAIL', j.client_email);
setKV('FIREBASE_CLIENT_ID', String(j.client_id));
setKV('FIREBASE_AUTH_URI', j.auth_uri);
setKV('FIREBASE_TOKEN_URI', j.token_uri);
setKV('FIREBASE_AUTH_PROVIDER_X509_CERT_URL', j.auth_provider_x509_cert_url);
setKV('FIREBASE_CLIENT_X509_CERT_URL', j.client_x509_cert_url);
setKV('GOOGLE_CLOUD_PROJECT_ID', j.project_id);
if (!/^(GOOGLE_APPLICATION_CREDENTIALS=)/m.test(env)) {
  setKV('GOOGLE_APPLICATION_CREDENTIALS', './service-account-key.json');
}

fs.writeFileSync(envPath, env);
console.log('# .env updated from service account');



