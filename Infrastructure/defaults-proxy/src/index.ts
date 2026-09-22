const upstreams: Record<string, string> = {
  "/even-more-gestures/defaults/stable.json": "https://raw.githubusercontent.com/parterburn/even-more-gestures/main/docs/defaults/stable.json",
  "/even-more-gestures/defaults/stable.sig": "https://raw.githubusercontent.com/parterburn/even-more-gestures/main/docs/defaults/stable.sig"
};

export default {
  async fetch(request: Request): Promise<Response> {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }

    const upstream = upstreams[new URL(request.url).pathname];
    if (!upstream) return new Response("Not found", { status: 404 });

    const response = await fetch(upstream, {
      cf: { cacheEverything: true, cacheTtl: 300 }
    });
    if (!response.ok) return new Response("Defaults are temporarily unavailable", { status: 502 });

    const headers = new Headers();
    headers.set("Content-Type", response.headers.get("Content-Type") ?? "application/octet-stream");
    headers.set("Cache-Control", "no-store");
    headers.set("X-Content-Type-Options", "nosniff");
    return new Response(request.method === "HEAD" ? null : response.body, { status: 200, headers });
  }
} satisfies ExportedHandler;
