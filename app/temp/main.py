#!/usr/bin/env python3
"""
FastAPI server for ResolveURL using libresolveurl
"""
import time
import re
import asyncio
import os
from concurrent.futures import ThreadPoolExecutor
from typing import List, Dict, Optional
from fastapi import FastAPI
from pydantic import BaseModel
from urllib.parse import unquote
import logging

# Setup config directories BEFORE importing libresolveurl
base_dir = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
data_dir = os.path.join(base_dir, "python_data")

# Create directories if they don't exist
os.makedirs(data_dir, exist_ok=True)
os.makedirs(os.path.join(data_dir, "resources"), exist_ok=True)

# Set environment variables BEFORE importing libresolveurl
os.environ.setdefault("LIBRESOLVEURL_CONFIG_DIR", data_dir)
os.environ.setdefault("LIBRESOLVEURL_ADDON_PATH", data_dir)

# Also patch the common module config before import
import sys
sys.path.insert(0, data_dir)

import libresolveurl

# Patch resolveurl.common.settings_file to use our data_dir
try:
    import resolveurl.common as common
    settings_dir = os.path.join(data_dir, "resources")
    os.makedirs(settings_dir, exist_ok=True)
    common.settings_file = os.path.join(settings_dir, "settings.xml")
except Exception as e:
    logging.warning(f"Could not patch resolveurl.common: {e}")


# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


# FastAPI app
app = FastAPI(title="ResolveURL Server")

class HostLink(BaseModel):
    url: str
    language: Optional[str] = ""
    quality: Optional[str] = ""
    headers: Optional[Dict[str, str]] = None

class ResolvedStream(BaseModel):
    host: str
    url: str
    headers: Dict[str, str]
    language: str
    quality: str
    duration: float = 0.0

def host_name(url: str) -> str:
    """Extract host name from URL"""
    m = re.search(r'://(?:www\.)?([^/]+)', url)
    return m.group(1).split('.')[0].upper() if m else 'UNKNOWN'

def resolve_url(url: str) -> Optional[str]:
    """Resolve a video URL using libresolveurl"""
    return libresolveurl.resolve(url)

def extract_quality_from_url(url: str) -> Optional[str]:
    """Extract quality keywords from URL as a last-resort fallback"""
    u = url.lower()
    if '4k' in u or '2160p' in u: return '4K'
    if '1080' in u or 'fhd' in u: return '1080p'
    if '720' in u or 'hd' in u: return '720p'
    if '480' in u or 'sd' in u: return '480p'
    if '360' in u: return '360p'
    return None

# Thread pool for concurrent resolution
executor = ThreadPoolExecutor(max_workers=10)

RESOLVE_TIMEOUT = 30  # seconds per link

async def resolve_single_link(item: HostLink) -> Optional[ResolvedStream]:
    """Resolve a single link asynchronously"""
    start_time = time.time()
    loop = asyncio.get_running_loop()

    # Run resolve_url in thread pool with per-link timeout
    try:
        resolved = await asyncio.wait_for(
            loop.run_in_executor(executor, resolve_url, item.url),
            timeout=RESOLVE_TIMEOUT,
        )
    except asyncio.TimeoutError:
        logger.warning(f"Resolve timeout for {item.url}")
        resolved = None

    # Initialize headers with Referer as fallback
    headers = {'Referer': item.url}
    # Merge headers from scraper if provided (can override Referer)
    if item.headers:
        headers.update(item.headers)

    if resolved:
        # Handle URLs with appended headers from ResolveURL
        if '|' in resolved:
            resolved_url, header_str = resolved.split('|', 1)
            for pair in header_str.split('&'):
                if '=' in pair:
                    k, v = pair.split('=', 1)
                    headers[k] = unquote(v)
            resolved = resolved_url
    else:
        # Fallback: return the original URL if resolution failed
        resolved = item.url

    final_quality = item.quality or extract_quality_from_url(resolved) or 'SD'
    duration = time.time() - start_time

    return ResolvedStream(
        host=host_name(item.url),
        url=resolved,
        headers=headers,
        language=item.language or '',
        quality=final_quality,
        duration=duration
    )

@app.post("/resolve", response_model=List[ResolvedStream])
async def resolve(links: List[HostLink]) -> List[ResolvedStream]:
    """Resolve multiple video URLs concurrently"""
    tasks = [resolve_single_link(item) for item in links]
    resolved_streams = await asyncio.gather(*tasks)
    results = [stream for stream in resolved_streams if stream is not None]
    return results

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
