# File Drop

A minimal web service to upload and download files.

- File metadata (id, name, size, upload date) is stored in **PostgreSQL**.
- File contents are stored on **local disk**, in the directory set by `DATA_DIR`.

The database table is created automatically when the application starts.

The service has no authentication. This is deliberate: authentication is out of scope for this exercise.

## Configuration

The application is configured only through environment variables.

| Variable       | Required | Default  | Description                                                              |
| -------------- | -------- | -------- | ------------------------------------------------------------------------ |
| `DATABASE_URL` | yes      |          | PostgreSQL connection string, e.g. `postgresql://user:pass@host:5432/db` |
| `DATA_DIR`     | no       | `./data` | Directory where uploaded files are stored. Created if missing.           |
| `PORT`         | no       | `8080`   | HTTP port the application listens on                                     |

## Run locally

### 1. Prerequisites

- Python 3.11 or later
- A PostgreSQL database (version 13 or later) that the application can reach

If you don't have PostgreSQL available, you can start one with Docker:

```sh
docker run -d --name filedrop-db \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  postgres:16
```

### 2. Install the dependencies

From this directory, create a virtual environment and install the dependencies:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Start the application

```sh
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/postgres
export DATA_DIR=./data
python app.py
```

The application listens on `http://localhost:8080`. It fails at startup if the database is unreachable.

### 4. Check that it works

```sh
curl localhost:8080/readyz
```

This returns `ok` when the application can reach the database and write to `DATA_DIR`.

## API

| Method | Path          | Description                                                     |
| ------ | ------------- | --------------------------------------------------------------- |
| POST   | `/files`      | Upload a file (multipart form, field `file`)                    |
| GET    | `/files`      | List uploaded files, most recent first                          |
| GET    | `/files/<id>` | Download a file                                                 |
| GET    | `/healthz`    | Liveness: the process is up                                     |
| GET    | `/readyz`     | Readiness: the database is reachable and `DATA_DIR` is writable |

## Example requests

### Upload a file

```sh
echo "hello" > notes.txt
curl -F file=@notes.txt localhost:8080/files
```

`-F file=@notes.txt` sends `notes.txt` as a multipart form field named `file`. The application writes the content to `DATA_DIR`, records its metadata in the database, and returns it with status `201`:

```json
{"id": "d68f972c819444faba8cea4db5b394d5", "name": "notes.txt", "size": 6}
```

Keep the `id`: you need it to download the file.

### List uploaded files

```sh
curl localhost:8080/files
```

This returns the metadata of every uploaded file, read from the database, most recent first:

```json
[{"created_at": "2026-10-19T07:51:08.838850+00:00", "id": "d68f972c819444faba8cea4db5b394d5", "name": "notes.txt", "size": 6}]
```

### Download a file

```sh
curl -OJ localhost:8080/files/d68f972c819444faba8cea4db5b394d5
```

Replace the id with the one returned by the upload. The application looks up the file name in the database and returns the content from `DATA_DIR`. `-O` saves the response to a file instead of printing it, and `-J` uses the original file name (`notes.txt`). An unknown id returns `404`.

### Check health

```sh
curl localhost:8080/healthz
curl -i localhost:8080/readyz
```

- `/healthz` returns `ok` as long as the process is running.
- `/readyz` returns `ok` with status `200` when the application is ready to serve requests. It returns status `503` with `database unreachable` or `data directory not writable` otherwise.
