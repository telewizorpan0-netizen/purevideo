"""
PureVideo Cast Proxy
====================

Mały serwer HTTP, który pozwala Google Cast (Chromecast / Android TV)
odtwarzać strumienie HLS (m3u8) wymagające nagłówków HTTP typu
Referer / User-Agent / Cookie.

Jak to działa
-------------
1. Aplikacja Flutter wysyla do Cast URL w formacie:
       http://<proxy>/hls?u=<base64url(URL)>&h=<base64url(JSON nagłówków)>
2. Proxy pobiera oryginalny URL z dokładnie tymi nagłówkami.
3. Dla playlist m3u8 przepisuje WSZYSTKIE wewnętrzne URL-e
   (warianty, segmenty, klucze AES, napisy, audio) na swoje URL-e
   proxy - dzięki temu Chromecast każdy segment też ściąga przez nas
   (z poprawnymi nagłówkami).
4. Dla segmentów (.ts, .m4s, .mp4, .vtt, klucze .key) zwraca surowe
   bajty strumieniowo.

Logi
----
Wszystkie requesty są logowane (poziom INFO) z czasem trwania
i statusem upstreamu, dzięki czemu łatwo zdiagnozować 403/404.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import re
import time
from typing import Any
from urllib.parse import quote, unquote, urljoin

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse

# --------------------------------------------------------------------------- #
#  Logger
# --------------------------------------------------------------------------- #

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-5s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("cast-proxy")

# --------------------------------------------------------------------------- #
#  HTTPX client (reużywany dla keep-alive)
# --------------------------------------------------------------------------- #

# verify=False bo niektóre CDN-y z IP w URL mają self-signed / mismatched SNI.
# To i tak jest proxy LAN - ryzyko akceptowalne.
_client: httpx.AsyncClient | None = None


def get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(
            timeout=httpx.Timeout(connect=10.0, read=30.0, write=30.0, pool=10.0),
            follow_redirects=True,
            verify=False,
            limits=httpx.Limits(max_keepalive_connections=32, max_connections=64),
            http2=False,
        )
    return _client


# --------------------------------------------------------------------------- #
#  FastAPI app
# --------------------------------------------------------------------------- #

app = FastAPI(
    title="PureVideo Cast Proxy",
    description="Proxy HTTP z doklejaniem nagłówków dla Google Cast",
    version="1.0.0",
)

# CORS - niepotrzebne dla Chromecasta (natywna ścieżka), ale przydaje się
# gdyby ktoś testował w przeglądarce / shaka-player-demo.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "HEAD", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["Content-Length", "Content-Range", "Accept-Ranges"],
)

# --------------------------------------------------------------------------- #
#  Kodowanie URL/headers
# --------------------------------------------------------------------------- #


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def encode_url(url: str) -> str:
    return _b64url_encode(url.encode("utf-8"))


def decode_url(token: str) -> str:
    return _b64url_decode(token).decode("utf-8")


def encode_headers(headers: dict[str, str] | None) -> str:
    payload = json.dumps(headers or {}, separators=(",", ":"), ensure_ascii=False)
    return _b64url_encode(payload.encode("utf-8"))


def decode_headers(token: str) -> dict[str, str]:
    if not token:
        return {}
    try:
        return json.loads(_b64url_decode(token).decode("utf-8"))
    except Exception as e:
        log.warning("Nieprawidłowy nagłówek b64 'h': %s", e)
        return {}


def build_proxy_url(
    base_url: str, original_url: str, headers: dict[str, str], endpoint: str
) -> str:
    """Buduje URL do samego siebie. `base_url` to np. http://192.168.1.100:8080"""
    u = encode_url(original_url)
    h = encode_headers(headers)
    return f"{base_url}/{endpoint}?u={u}&h={h}"


# --------------------------------------------------------------------------- #
#  Normalizacja nagłówków
# --------------------------------------------------------------------------- #

# Nagłówki, które NIE mają być przekazywane do upstreamu (hop-by-hop
# i te, które httpx ustawi lepiej sam).
_DROP_UPSTREAM = {
    "host",
    "content-length",
    "accept-encoding",
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


def sanitize_upstream_headers(h: dict[str, str]) -> dict[str, str]:
    return {k: v for k, v in h.items() if k.lower() not in _DROP_UPSTREAM}


# Nagłówki odpowiedzi, których nie chcemy puszczać do klienta
_DROP_RESPONSE = {
    "content-encoding",  # upstream może wysłać gzip; my forwardujemy bajty
    "content-length",    # przy chunked/streaming niepoprawne
    "transfer-encoding",
    "connection",
    "keep-alive",
}


def sanitize_response_headers(h: httpx.Headers) -> dict[str, str]:
    return {k: v for k, v in h.items() if k.lower() not in _DROP_RESPONSE}


# --------------------------------------------------------------------------- #
#  Wykrywanie typu zawartości
# --------------------------------------------------------------------------- #

_HLS_MIME = "application/vnd.apple.mpegurl"
_DASH_MIME = "application/dash+xml"


def guess_content_type(url: str, upstream_ct: str | None) -> str:
    lower = url.lower().split("?", 1)[0]
    if lower.endswith(".m3u8"):
        return _HLS_MIME
    if lower.endswith(".mpd"):
        return _DASH_MIME
    if lower.endswith(".mp4") or lower.endswith(".m4v") or lower.endswith(".m4s"):
        return "video/mp4"
    if lower.endswith(".ts"):
        return "video/mp2t"
    if lower.endswith(".vtt"):
        return "text/vtt"
    if lower.endswith(".webm"):
        return "video/webm"
    if upstream_ct:
        return upstream_ct
    return "application/octet-stream"


def looks_like_hls(url: str, upstream_ct: str | None, body_head: bytes | None) -> bool:
    lower = url.lower().split("?", 1)[0]
    if lower.endswith(".m3u8"):
        return True
    if upstream_ct and ("mpegurl" in upstream_ct.lower() or "hls" in upstream_ct.lower()):
        return True
    if body_head and body_head.lstrip().startswith(b"#EXTM3U"):
        return True
    return False


# --------------------------------------------------------------------------- #
#  Przepisywanie playlist HLS
# --------------------------------------------------------------------------- #

# Linie w m3u8, które ZAWIERAJĄ URL w atrybucie URI="..."
_URI_ATTR_RE = re.compile(r'(URI=)"([^"]+)"', re.IGNORECASE)


def rewrite_hls_playlist(
    body: str,
    base_url: str,          # URL publiczny tego proxy (np. http://192.168.1.100:8080)
    manifest_url: str,      # URL manifestu upstreamowego (do resolve relatywnych)
    headers: dict[str, str],
) -> str:
    """Przepisuje wszystkie URL-e w playliście HLS na URL-e proxy."""
    manifest_base = manifest_url.rsplit("/", 1)[0] + "/"
    out_lines: list[str] = []

    for raw in body.splitlines():
        line = raw.rstrip("\r")

        # Tagi (#...) - mogą mieć atrybut URI="..."
        if line.startswith("#"):
            if "URI=" in line.upper():
                def _sub(m: re.Match[str]) -> str:
                    inner = m.group(2)
                    absu = urljoin(manifest_base, inner)
                    # Key, media (audio/subs), i-frame - wszystko per-segment lub per-playlist.
                    # Traktujemy je jako segment (mogą być .m3u8, .key, .ts itd.).
                    proxied = build_proxy_url(base_url, absu, headers, "seg")
                    # Ale jeśli rozszerzenie to .m3u8 - przerób na /hls żeby
                    # rekurencyjnie przepisać:
                    if absu.lower().split("?", 1)[0].endswith(".m3u8"):
                        proxied = build_proxy_url(base_url, absu, headers, "hls")
                    return f'{m.group(1)}"{proxied}"'
                line = _URI_ATTR_RE.sub(_sub, line)
            out_lines.append(line)
            continue

        # Pusta linia
        if not line.strip():
            out_lines.append(line)
            continue

        # Normalna linia - to URI do wariantu/segmentu
        absu = urljoin(manifest_base, line.strip())
        lower = absu.lower().split("?", 1)[0]
        endpoint = "hls" if lower.endswith(".m3u8") else "seg"
        out_lines.append(build_proxy_url(base_url, absu, headers, endpoint))

    # HLS wymaga \n lub \r\n; używamy \n.
    return "\n".join(out_lines) + "\n"


# --------------------------------------------------------------------------- #
#  Ustalanie public base URL (do przepisywania m3u8)
# --------------------------------------------------------------------------- #


def resolve_public_base(request: Request) -> str:
    """Zwraca bazę URL, pod którą klient (Chromecast) zapyta proxy.
    Bierze to z nagłówka Host requesta, żeby działało niezależnie od tego
    na jakim IP/porcie proxy jest dostępne.
    """
    # Host = IP:port (Chromecast wysyła taki sam Host, jaki mu wysłał Sender).
    # Scheme zakładamy http - w LAN nie używamy TLS.
    scheme = "https" if request.headers.get("x-forwarded-proto") == "https" else "http"
    host = request.headers.get("host") or f"{request.url.hostname}:{request.url.port}"
    return f"{scheme}://{host}"


# --------------------------------------------------------------------------- #
#  Endpointy
# --------------------------------------------------------------------------- #


@app.get("/", response_class=PlainTextResponse)
async def root() -> str:
    return (
        "PureVideo Cast Proxy - OK\n"
        "Endpoints:\n"
        "  /health            - healthcheck\n"
        "  /hls?u=<b64>&h=<b64>  - playlista HLS (przepisywana)\n"
        "  /seg?u=<b64>&h=<b64>  - segment/klucz/dowolny zasób (pass-through)\n"
        "  /probe?u=<URL>&h=<JSON> - pomocniczy: spr. czy upstream odpowiada 200\n"
    )


@app.get("/health", response_class=PlainTextResponse)
async def health() -> str:
    return "ok"


@app.get("/hls")
async def hls(u: str, h: str = "", request: Request = None) -> Response:
    """Zwraca playlistę HLS z przepisanymi linkami."""
    try:
        url = decode_url(u)
    except Exception:
        raise HTTPException(400, "Zły parametr u")
    headers = sanitize_upstream_headers(decode_headers(h))
    base = resolve_public_base(request)

    t0 = time.monotonic()
    client = get_client()
    try:
        r = await client.get(url, headers=headers)
    except httpx.HTTPError as e:
        log.warning("HLS upstream error url=%s err=%s", url, e)
        raise HTTPException(502, f"Upstream error: {e}")

    elapsed = (time.monotonic() - t0) * 1000
    log.info("HLS  %s %s  %.0fms  %d bajtów", r.status_code, url, elapsed, len(r.content))

    if r.status_code >= 400:
        # Zwróć tekst błędu upstreamu - łatwiejszy debug
        return Response(
            content=r.content,
            status_code=r.status_code,
            media_type=r.headers.get("content-type", "text/plain"),
        )

    body = r.text
    if not body.lstrip().startswith("#EXTM3U"):
        # To nie jest m3u8 - oddaj surowo
        log.info("HLS  %s nie wygląda na m3u8, przełączam na pass-through", url)
        return Response(
            content=r.content,
            status_code=r.status_code,
            media_type=r.headers.get("content-type", "application/octet-stream"),
            headers=sanitize_response_headers(r.headers),
        )

    rewritten = rewrite_hls_playlist(body, base, url, decode_headers(h))
    return Response(
        content=rewritten,
        status_code=200,
        media_type=_HLS_MIME,
        headers={"Cache-Control": "no-store"},
    )


@app.get("/seg")
@app.head("/seg")
async def seg(u: str, h: str = "", request: Request = None) -> Response:
    """Pass-through dla segmentów / kluczy / subtitles / wszystkiego co nie-m3u8.
    Obsługuje Range (niezbędne dla MP4 i Chromecasta)."""
    try:
        url = decode_url(u)
    except Exception:
        raise HTTPException(400, "Zły parametr u")
    headers = sanitize_upstream_headers(decode_headers(h))

    # Przekazuj Range / If-Modified-Since itp. z requesta klienta
    for passthru in ("range", "if-modified-since", "if-none-match"):
        val = request.headers.get(passthru)
        if val is not None:
            headers[passthru.title()] = val

    t0 = time.monotonic()
    client = get_client()
    method = request.method

    # Używamy stream=True, ale budujemy request ręcznie żeby obsłużyć HEAD.
    try:
        req = client.build_request(method, url, headers=headers)
        upstream = await client.send(req, stream=True)
    except httpx.HTTPError as e:
        log.warning("SEG  upstream error url=%s err=%s", url, e)
        raise HTTPException(502, f"Upstream error: {e}")

    elapsed = (time.monotonic() - t0) * 1000
    log.info("SEG  %s %s %s  %.0fms", method, upstream.status_code, url, elapsed)

    out_headers = sanitize_response_headers(upstream.headers)
    media_type = out_headers.pop("content-type", None) or guess_content_type(
        url, upstream.headers.get("content-type")
    )

    if method == "HEAD":
        await upstream.aclose()
        return Response(
            status_code=upstream.status_code, headers=out_headers, media_type=media_type
        )

    async def body_iter() -> Any:
        try:
            async for chunk in upstream.aiter_raw():
                yield chunk
        finally:
            await upstream.aclose()

    return StreamingResponse(
        body_iter(),
        status_code=upstream.status_code,
        headers=out_headers,
        media_type=media_type,
    )


@app.get("/probe")
async def probe(u: str, h: str = "") -> dict[str, Any]:
    """Endpoint diagnostyczny - NIE przepisuje treści, tylko mówi czy upstream
    odpowiedział 200. Przydaje się z 'Testuj połączenie' w aplikacji Flutter."""
    try:
        url = decode_url(u) if not u.startswith(("http://", "https://")) else u
    except Exception:
        raise HTTPException(400, "Zły parametr u")
    try:
        hd = decode_headers(h) if h and not h.startswith("{") else (json.loads(h) if h else {})
    except Exception:
        hd = {}
    headers = sanitize_upstream_headers(hd)
    client = get_client()
    t0 = time.monotonic()
    try:
        r = await client.get(url, headers=headers)
        elapsed = (time.monotonic() - t0) * 1000
        return {
            "ok": r.status_code == 200,
            "status": r.status_code,
            "elapsed_ms": round(elapsed),
            "content_type": r.headers.get("content-type"),
            "size": len(r.content),
        }
    except httpx.HTTPError as e:
        return {"ok": False, "error": str(e)}


# --------------------------------------------------------------------------- #
#  Graceful shutdown
# --------------------------------------------------------------------------- #


@app.on_event("shutdown")
async def _shutdown() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
    log.info("Client closed")


# --------------------------------------------------------------------------- #
#  CLI / standalone uvicorn
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import os

    import uvicorn

    uvicorn.run(
        "proxy:app",
        host=os.environ.get("PROXY_HOST", "0.0.0.0"),
        port=int(os.environ.get("PROXY_PORT", "8080")),
        log_level="info",
        access_log=False,  # loggujemy sami - mniej spamu
    )
