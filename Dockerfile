FROM python:3.15-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DATA_DIR=/data \
    PORT=8080

WORKDIR /app

COPY filedrop/requirements.txt .
RUN pip install -r requirements.txt gunicorn==26.2.0

COPY filedrop/app.py .

RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app \
    && mkdir -p /data && chown app /data
USER 10001

EXPOSE 8080

# --preload imports app.py once in the master, so init() (CREATE TABLE) runs a
# single time instead of once per worker.
CMD ["sh", "-c", "exec gunicorn --preload --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --timeout 120 --access-logfile - --no-control-socket app:app"]
