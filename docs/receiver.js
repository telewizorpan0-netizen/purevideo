/**
 * PureVideo Custom Cast Receiver
 *
 * What this does:
 *  1. Reads `customData.headers` from the LOAD message sent by the Flutter
 *     app and stores them globally.
 *  2. Forces a sane contentType when the sender did not provide one or
 *     provided a generic value.
 *  3. Adds the captured HTTP headers (Referer, User-Agent, Origin, ...)
 *     to every outgoing media request that shaka-player makes (manifest,
 *     segment, license). Without this Polish hosters reject the requests
 *     with 403 / 404.
 *  4. Filters out non-HTTP "headers" (e.g. resolveurl-specific flags like
 *     `verifypeer`) before they leak into XHRs.
 *
 * Important: DO NOT trust HTML-loaded plain comments to be visible at runtime
 * in the receiver - the device console is the only window into what's
 * happening. We log a lot, then turn it down later.
 */

const TAG = '[PureVideo]';
const HOP_BY_HOP = new Set([
  'host',
  'content-length',
  'connection',
  'keep-alive',
  'transfer-encoding',
  'upgrade',
  'expect',
  // resolveurl flag, not a real HTTP header
  'verifypeer',
]);

/** Headers from the most recent LOAD. Reused for every subsequent XHR. */
let currentHeaders = {};

/**
 * Sanitize the headers map: strip null/undefined, hop-by-hop and
 * resolveurl-specific flags. Returns a plain `{ name: value }` object.
 */
function sanitizeHeaders(input) {
  const out = {};
  if (!input || typeof input !== 'object') return out;
  for (const rawKey of Object.keys(input)) {
    if (rawKey == null) continue;
    const key = String(rawKey).trim();
    if (!key) continue;
    if (HOP_BY_HOP.has(key.toLowerCase())) continue;
    const val = input[rawKey];
    if (val == null) continue;
    out[key] = String(val);
  }
  return out;
}

/**
 * Pick a contentType based on the URL extension when the sender did not
 * provide one (or provided application/octet-stream which CAF refuses to
 * route to shaka).
 */
function guessContentType(url) {
  if (!url) return null;
  const lower = url.toLowerCase().split('?')[0];
  if (lower.endsWith('.m3u8') || lower.includes('.m3u8')) {
    return 'application/x-mpegURL';
  }
  if (lower.endsWith('.mpd')) return 'application/dash+xml';
  if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
  if (lower.endsWith('.webm')) return 'video/webm';
  return null;
}

const context = cast.framework.CastReceiverContext.getInstance();
const playerManager = context.getPlayerManager();

/* ---------- 1) LOAD interceptor: capture headers, fix contentType ---------- */

playerManager.setMessageInterceptor(
  cast.framework.messages.MessageType.LOAD,
  (request) => {
    try {
      const media = request.media || {};
      const customData = request.customData || media.customData || {};
      currentHeaders = sanitizeHeaders(customData.headers);

      console.log(TAG, 'LOAD', {
        contentId: media.contentId,
        contentType: media.contentType,
        headerKeys: Object.keys(currentHeaders),
        proxy: customData.proxy,
      });

      // contentUrl is preferred over the legacy contentId in CAF v3,
      // but Flutter sender uses contentId. Mirror it both ways so shaka
      // gets the URL no matter which path CAF picks.
      if (!media.contentUrl && media.contentId) {
        media.contentUrl = media.contentId;
      }

      // Fix bogus content types so shaka actually loads the manifest.
      const guess = guessContentType(media.contentUrl || media.contentId);
      if (guess) {
        if (!media.contentType ||
            media.contentType === 'application/octet-stream') {
          media.contentType = guess;
        }
      }
    } catch (e) {
      console.error(TAG, 'LOAD interceptor error:', e);
    }
    return request;
  }
);

/* ---------- 2) Per-request header injection via PlaybackConfig ---------- */

/**
 * Wrap a NetworkRequestInfo so it carries our captured headers. The same
 * shape works for manifest, segment, and license requests.
 */
function attachHeaders(requestInfo, kind) {
  if (!requestInfo) return requestInfo;
  requestInfo.headers = Object.assign({}, requestInfo.headers, currentHeaders);
  // withCredentials false is a safer default - we send Referer/Origin
  // explicitly via headers, not via cookies.
  requestInfo.withCredentials = false;
  if (console && console.debug) {
    console.debug(TAG, kind, requestInfo.url);
  }
  return requestInfo;
}

playerManager.setMediaPlaybackInfoHandler((loadRequest, playbackConfig) => {
  // Reset and re-attach handlers per LOAD - keeps things deterministic.
  playbackConfig.manifestRequestHandler = (requestInfo) =>
    attachHeaders(requestInfo, 'manifest');
  playbackConfig.segmentRequestHandler = (requestInfo) =>
    attachHeaders(requestInfo, 'segment');
  playbackConfig.licenseRequestHandler = (requestInfo) =>
    attachHeaders(requestInfo, 'license');

  // Generous timeouts - hosters via Cloudflare quick tunnel can be slow
  // on the first request after idle.
  playbackConfig.manifestRequestTimeout = 30 * 1000;
  playbackConfig.segmentRequestTimeout = 30 * 1000;

  return playbackConfig;
});

/* ---------- 3) Error visibility ---------- */

playerManager.addEventListener(
  cast.framework.events.EventType.ERROR,
  (event) => {
    console.error(TAG, 'ERROR', {
      detailedErrorCode: event.detailedErrorCode,
      reason: event.reason,
      error: event.error,
    });
  }
);

/* ---------- 4) Start ---------- */

const options = new cast.framework.CastReceiverOptions();
// Surface log entries in the Cast Console "Debug Logger" tab.
options.disableIdleTimeout = false;
options.statusText = 'PureVideo';

context.start(options);

console.log(TAG, 'receiver started');
