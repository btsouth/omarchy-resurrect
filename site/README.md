# ress.sh

The link shortener for Resurrect loadouts. It redirects and does nothing else:

```
ress.sh/gh/<user>/<repo>  ->  github.com/<user>/<repo>
ress.sh/repo              ->  this project
```

No storage, no accounts, no user content. GitHub hosts every profile; this only
makes the line short enough to paste into a message. `ress apply` expands the
link locally before it makes a request, so the shortener is never in the path of
anything that matters — and plain GitHub URLs work everywhere a short link does.

## Deploy (Cloudflare Pages — recommended)

```bash
npx wrangler pages deploy site --project-name ress
```

Then point the `ress.sh` apex at the Pages project in the Cloudflare dashboard.
`_redirects` does the routing; there is no code to run.

## Deploy (Cloudflare Worker — alternative)

`worker.js` is the same routing as a Worker, for a Workers-only setup. Bind the
`site/` directory as the `ASSETS` binding if you want it to serve the landing
page too.
