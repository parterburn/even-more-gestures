# Defaults proxy

This Cloudflare Worker serves the signed defaults feed from the product domain:

- `https://paularterburn.com/even-more-gestures/defaults/stable.json`
- `https://paularterburn.com/even-more-gestures/defaults/stable.sig`

It only proxies those two fixed, public GitHub files. Cloudflare retains aggregate request analytics for the paths, which provides an estimated daily-active-installation count without accounts or an install identifier.

Deploy with:

```sh
cd Infrastructure/defaults-proxy
npx wrangler deploy
```

The app retains GitHub Raw as a fallback if the proxy is temporarily unavailable.
