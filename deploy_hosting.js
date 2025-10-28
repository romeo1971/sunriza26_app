const { google } = require('googleapis');
const fs = require('fs');

async function deployHosting() {
  const auth = new google.auth.GoogleAuth({
    keyFile: '/Users/hhsw/Desktop/sunriza/shell_json/sunriza26-firebase-adminsdk-fbsvc-4bcb6d827b.json',
    scopes: ['https://www.googleapis.com/auth/cloud-platform']
  });

  const client = await auth.getClient();

  const url = 'https://firebasehosting.googleapis.com/v1beta1/sites/sunriza26/releases';
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${(await client.getAccessToken()).token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      // hier Deployment-Daten einfügen
    })
  });

  console.log(await res.json());
}

deployHosting();

