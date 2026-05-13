# Lekki obraz (~110 MB po build)
FROM python:3.12-alpine

# httpx + pydantic (FastAPI) mają C-speedups, ale działają też bez nich.
# Alpine wystarczy - nie potrzebujemy gcc.

WORKDIR /app

# Najpierw deps - lepsza warstwowość cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY proxy.py .

ENV PROXY_HOST=0.0.0.0
ENV PROXY_PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["python", "-u", "proxy.py"]
