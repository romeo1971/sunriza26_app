from fastapi import FastAPI
from fastapi.responses import JSONResponse
import uvicorn

app = FastAPI()

@app.get("/")
async def root():
    """Backend ist jetzt nur noch für andere Services da - BitHuman übernimmt Avatar-Generierung"""
    return {"message": "Backend läuft - Avatar-Generierung erfolgt über BitHuman SDK"}

@app.get("/health")
async def health():
    """Health Check für das Backend"""
    return {"status": "healthy", "service": "sunriza26-backend"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
