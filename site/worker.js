// ress.sh as a Cloudflare Worker, for anyone who would rather run this than
// Pages + _redirects. It does one thing: rewrite a path to a GitHub URL.
//
// No storage, no state, no request body is ever read. A profile is hosted by
// GitHub and nowhere else; this only shortens the line that points at it.

const REPO = "https://github.com/tsouth89/omarchy-resurrect";
const RAW = "https://raw.githubusercontent.com/tsouth89/omarchy-resurrect/main";

// Deliberately narrow: GitHub's own character set for owners and repos, and
// nothing that could turn a path into a different host.
const GH = /^\/gh\/([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))\/([A-Za-z0-9._-]{1,100})\/?$/;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    const gh = url.pathname.match(GH);
    if (gh) return Response.redirect(`https://github.com/${gh[1]}/${gh[2]}`, 302);

    if (url.pathname === "/bootstrap") return Response.redirect(`${RAW}/bin/resurrect-bootstrap`, 302);
    if (url.pathname === "/repo") return Response.redirect(REPO, 302);
    if (url.pathname === "/" || url.pathname === "/index.html") {
      return env.ASSETS ? env.ASSETS.fetch(request) : Response.redirect(REPO, 302);
    }

    return new Response("Not found. A ress.sh link looks like ress.sh/gh/<user>/<repo>.\n", {
      status: 404,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  },
};
