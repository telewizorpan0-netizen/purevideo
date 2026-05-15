# PureVideo Cast Receiver

This folder is served by GitHub Pages and hosts the Custom Web Receiver
used by the PureVideo Flutter app for casting HLS / fMP4 streams to
Chromecast / Android TV.

Files:
- `index.html` - shell with the `<cast-media-player>` element and the
  CAF v3 SDK script tag.
- `receiver.js` - LOAD message interceptor (extracts HTTP headers from
  `customData.headers`) and `setMediaPlaybackInfoHandler` (injects
  those headers into every manifest / segment / license request).

After enabling GitHub Pages on this branch with folder `/docs`, the
public URL will be:

```
https://<your-github-username>.github.io/purevideo/
```

That URL goes into the Cast Console "Receiver application URL" field.
The 8-character Application ID issued by the Cast Console then goes into
the PureVideo app: `Settings -> Cast -> Receiver Application ID`.
