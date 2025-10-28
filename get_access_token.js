const { google } = require('googleapis');

async function getAccessToken() {
  const auth = new google.auth.GoogleAuth({
    keyFile: '/Users/hhsw/Desktop/sunriza/shell_json/sunriza26-firebase-adminsdk-fbsvc-4bcb6d827b.json',
    scopes: ['https://www.googleapis.com/auth/cloud-platform']
  });

  const client = await auth.getClient();
  const accessToken = (await client.getAccessToken()).token;
  console.log('Access Token:', accessToken);
}

getAccessToken();

