import os
import modal

# Image: Debian + Node.js + unser Code
image = (
    modal.Image.debian_slim()
    .apt_install("bash", "nodejs", "npm", "git")
    .add_local_dir("./orchestrator", "/app/orchestrator", copy=True)
    .run_commands([
        "bash -lc 'cd /app/orchestrator && npm ci --ignore-scripts'",
        "bash -lc 'cd /app/orchestrator && npm run build'",
    ])
)

app = modal.App("lipsync-orchestrator", image=image)


@app.function(
    secrets=[modal.Secret.from_name("lipsync-eleven")],
    env={
        "PORT": "3001",
        "ELEVENLABS_BASE": os.getenv("ELEVENLABS_BASE", "api.elevenlabs.io"),
        "ELEVENLABS_MODEL_ID": os.getenv(
            "ELEVENLABS_MODEL_ID", "eleven_multilingual_v2"
        ),
    },
)
@modal.concurrent(max_inputs=100)
@modal.web_server(3001)
def web():
    # Startet den vorhandenen Node-WS-Server
    import subprocess
    os.chdir("/app/orchestrator")
    # Nur starten (Build bereits im Image erledigt)
    subprocess.Popen("node dist/lipsync_handler.js", shell=True)


