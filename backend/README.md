Backend – Avatar Memory (FastAPI)

Start lokal:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Env (.env im Projektroot):

```
OPENAI_API_KEY=...
PINECONE_API_KEY=...
PINECONE_CLOUD=aws
PINECONE_REGION=us-east-1
PINECONE_INDEX=avatars-index
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_DIM=1536
```

Endpoint:

HINWEIS: Lokale Endpoints (127.0.0.1) sind obsolet. Die App kann im Demo-Modus ohne Backend laufen. Für echte Backends nutze die Cloud-Run-URL und ersetze 127.0.0.1 entsprechend.

Body:

```json
{
  "user_id": "<uid>",
  "avatar_id": "<avatarId>",
  "full_text": "Langer Text ...",
  "source": "optional-datei.txt"
}
```


