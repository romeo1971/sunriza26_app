from flask import Flask, request, jsonify
from google.cloud import storage
import base64
import os

# OpenTimestamps (Python)
from opentimestamps.core.op import OpSHA256
from opentimestamps.core.timestamp import DetachedTimestampFile
from opentimestamps.client import stamp, upgrade

app = Flask(__name__)


def _signed_url(bucket: str, path: str, minutes: int = 60*24*30) -> str:
    client = storage.Client()
    b = client.bucket(bucket)
    blob = b.blob(path)
    return blob.generate_signed_url(expiration=minutes*60)


@app.post('/stamp')
def stamp_endpoint():
    data = request.get_json(force=True)
    bucket = data.get('bucket')
    dest_path = data.get('destPath')  # e.g., invoices/uid/file.pdf.ots
    hash_hex = (data.get('hashHex') or '').strip()
    if not bucket or not dest_path or len(hash_hex) != 64:
        return jsonify({'error': 'invalid-args'}), 400

    # Build OTS from SHA256
    h = bytes.fromhex(hash_hex)
    dtf = DetachedTimestampFile.from_hash(OpSHA256(), h)
    # send to calendars
    stamp(dtf)
    proof = dtf.serialize_to_bytes()

    # Save to GCS
    client = storage.Client()
    b = client.bucket(bucket)
    blob = b.blob(dest_path)
    blob.upload_from_string(proof, content_type='application/ots')

    url = _signed_url(bucket, dest_path)
    return jsonify({'ok': True, 'otsUrl': url})


@app.post('/upgrade')
def upgrade_endpoint():
    data = request.get_json(force=True)
    bucket = data.get('bucket')
    dest_path = data.get('destPath')  # same path as saved .ots
    if not bucket or not dest_path:
        return jsonify({'error': 'invalid-args'}), 400

    client = storage.Client()
    b = client.bucket(bucket)
    blob = b.blob(dest_path)
    if not blob.exists():
        return jsonify({'ok': False, 'reason': 'not-found'}), 404

    proof = blob.download_as_bytes()
    dtf = DetachedTimestampFile.deserialize(proof)
    # Try upgrading with calendars
    try:
        upgrade(dtf)
        upgraded = dtf.serialize_to_bytes()
        blob.upload_from_string(upgraded, content_type='application/ots')
        url = _signed_url(bucket, dest_path)
        return jsonify({'ok': True, 'otsUrl': url})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.get('/health')
def health():
    return jsonify({'ok': True})


if __name__ == '__main__':
    port = int(os.environ.get('PORT', '8080'))
    app.run(host='0.0.0.0', port=port)


