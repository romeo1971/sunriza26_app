// Web Audio Recording für STT (Speech-to-Text)
// Nutzt MediaRecorder API und exportiert Blob als Uint8Array an Flutter.

let mediaRecorder = null;
let audioChunks = [];
let audioStream = null;

// Startet Audio-Aufnahme (Web getUserMedia)
window.startWebAudioRecording = async function() {
  try {
    if (mediaRecorder && mediaRecorder.state === 'recording') {
      console.warn('[STT] Aufnahme läuft bereits');
      return { success: false, error: 'Already recording' };
    }
    audioStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    audioChunks = [];
    
    // Prefer webm/opus for best compatibility with Whisper
    const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      ? 'audio/webm;codecs=opus'
      : 'audio/webm';
    
    mediaRecorder = new MediaRecorder(audioStream, { mimeType });
    
    mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        audioChunks.push(event.data);
      }
    };
    
    mediaRecorder.start();
    console.log('[STT] Aufnahme gestartet');
    return { success: true };
  } catch (error) {
    console.error('[STT] Start-Fehler:', error);
    return { success: false, error: error.message };
  }
};

// Stoppt Audio-Aufnahme und gibt Uint8Array zurück
window.stopWebAudioRecording = async function() {
  return new Promise((resolve, reject) => {
    if (!mediaRecorder || mediaRecorder.state === 'inactive') {
      console.warn('[STT] Keine aktive Aufnahme');
      resolve({ success: false, error: 'No active recording' });
      return;
    }
    
    mediaRecorder.onstop = async () => {
      try {
        const audioBlob = new Blob(audioChunks, { type: mediaRecorder.mimeType });
        const arrayBuffer = await audioBlob.arrayBuffer();
        const uint8Array = new Uint8Array(arrayBuffer);
        
        // Cleanup
        if (audioStream) {
          audioStream.getTracks().forEach(track => track.stop());
          audioStream = null;
        }
        mediaRecorder = null;
        audioChunks = [];
        
        console.log(`[STT] Aufnahme gestoppt, ${uint8Array.length} bytes`);
        resolve({ success: true, data: uint8Array, mimeType: audioBlob.type });
      } catch (error) {
        console.error('[STT] Stop-Fehler:', error);
        reject({ success: false, error: error.message });
      }
    };
    
    mediaRecorder.stop();
  });
};

// Prüft, ob Browser MediaRecorder unterstützt
window.isWebAudioRecordingSupported = function() {
  return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
};

