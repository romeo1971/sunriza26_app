const { exec } = require('child_process');

exec('firebase deploy --project sunriza26', (err, stdout, stderr) => {
  if (err) {
    console.error('Deploy Fehler:', err);
    return;
  }
  console.log(stdout);
});
