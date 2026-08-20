# ress.sh

The link shortener for ress loadouts. It redirects and does nothing else:

```
ress.sh/gh/<user>/<repo>  ->  github.com/<user>/<repo>
ress.sh/repo              ->  this project
```

No storage, no accounts, no user content. GitHub hosts every profile; this only
makes the line short enough to paste into a message. `ress apply` expands the
link locally before it makes a request, so the shortener is never in the path of
anything that matters — and plain GitHub URLs work everywhere a short link does.

## Layout

Only `public/` is published. `worker.js` and this file stay out of the deploy,
so nothing is served at `ress.sh/worker.js`.

```
site/public/index.html    the landing page
site/public/_redirects    the routing table
site/worker.js            the Workers alternative (not deployed)
```

## Deploy (Cloudflare Pages — recommended)

```bash
npx wrangler pages project create ress --production-branch main
npx wrangler pages deploy site/public --project-name ress
```

Both commands need `CLOUDFLARE_API_TOKEN` (Account → Cloudflare Pages → Edit)
and `CLOUDFLARE_ACCOUNT_ID` in the environment. The account ID is only needed
because a Pages-scoped token cannot enumerate accounts by itself.

Then point the `ress.sh` apex at the Pages project in the Cloudflare dashboard.
`_redirects` does the routing; there is no code to run.

## Deploy (Cloudflare Worker — alternative)

`worker.js` is the same routing as a Worker, for a Workers-only setup. Bind the
`site/` directory as the `ASSETS` binding if you want it to serve the landing
page too.
