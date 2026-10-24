import os
import uuid

import psycopg
from flask import Flask, abort, jsonify, request, send_file

DATABASE_URL = os.environ["DATABASE_URL"]
DATA_DIR = os.environ.get("DATA_DIR", "./data")
PORT = int(os.environ.get("PORT", "8080"))

app = Flask(__name__)


def db():
    return psycopg.connect(DATABASE_URL)


def init():
    os.makedirs(DATA_DIR, exist_ok=True)
    with db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS files (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                size INTEGER NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )


@app.post("/files")
def upload():
    f = request.files.get("file")
    if f is None:
        abort(400, "missing 'file' field")

    file_id = uuid.uuid4().hex
    path = os.path.join(DATA_DIR, file_id)
    f.save(path)
    size = os.path.getsize(path)

    with db() as conn:
        conn.execute(
            "INSERT INTO files (id, name, size) VALUES (%s, %s, %s)",
            (file_id, f.filename, size),
        )
    return jsonify(id=file_id, name=f.filename, size=size), 201


@app.get("/files")
def list_files():
    with db() as conn:
        rows = conn.execute(
            "SELECT id, name, size, created_at FROM files ORDER BY created_at DESC"
        ).fetchall()
    return jsonify(
        [
            {"id": r[0], "name": r[1], "size": r[2], "created_at": r[3].isoformat()}
            for r in rows
        ]
    )


@app.get("/files/<file_id>")
def download(file_id):
    with db() as conn:
        row = conn.execute("SELECT name FROM files WHERE id = %s", (file_id,)).fetchone()
    if row is None:
        abort(404)
    return send_file(os.path.join(DATA_DIR, file_id), download_name=row[0], as_attachment=True)


@app.get("/healthz")
def healthz():
    return "ok"


@app.get("/readyz")
def readyz():
    try:
        with db() as conn:
            conn.execute("SELECT 1")
    except psycopg.Error:
        return "database unreachable", 503
    if not os.access(DATA_DIR, os.W_OK):
        return "data directory not writable", 503
    return "ok"


init()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
