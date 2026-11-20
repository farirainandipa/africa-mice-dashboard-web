// Pass 1 for the bid history layer: read the public ICCA Bid Wins feed
// (WordPress REST API on iccaworld.org), and hand every post not yet stored to
// public.history_ingest_icca(), which creates candidate bid_wins rows at
// Tier 2 / Unverified and matches or creates the series.
//
// Called weekly by pg_cron (job icca_bid_wins_weekly) and on demand by an admin
// from the pipeline's Bid History tab. Idempotent: posts already stored are
// skipped. Non-admin calls are limited to one run per 6 hours.
//
// Only the title, date, link and the first 14 words of each post leave this
// function; ICCA article text is never stored in full, and no ICCA logo or
// branding is copied.
//
// IP website change W5: every run reads iccaworld.org/robots.txt first and
// stops if the feed path is disallowed, waits at least REQUEST_GAP_MS between
// requests (longer if robots.txt sets a Crawl-delay), and records the robots
// check in history_sync_log.result.robots.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "content-type": "application/json" } });

const ORIGIN = "https://www.iccaworld.org";
const WP = `${ORIGIN}/wp-json/wp/v2`;
const UA_TOKEN = "FNMICE-Pipeline";
const UA = `${UA_TOKEN}/1.0 (bid history scan)`;
const REQUEST_GAP_MS = 3000;
const PATHS = ["/wp-json/wp/v2/categories", "/wp-json/wp/v2/posts"];

const ENT: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ndash: "-", mdash: "-", rsquo: "'", lsquo: "'", rdquo: '"', ldquo: '"', hellip: "..." };
function decode(s: string): string {
  return s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, n) => ENT[n.toLowerCase()] ?? m)
    .replace(/[–—]/g, "-");
}
const strip = (h: string) => decode((h || "").replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
const firstWords = (s: string, n = 14) => s.split(/\s+/).filter(Boolean).slice(0, n).join(" ");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type Robots = { checked_at: string; status: number | null; allowed: boolean; crawl_delay_s: number | null; rule: string | null };

/** Reads robots.txt and applies the group for our user agent (or *), longest match wins, Allow beats Disallow on a tie. */
async function checkRobots(): Promise<Robots> {
  const out: Robots = { checked_at: new Date().toISOString(), status: null, allowed: true, crawl_delay_s: null, rule: null };
  const r = await fetch(`${ORIGIN}/robots.txt`, { headers: { "User-Agent": UA } });
  out.status = r.status;
  if (r.status >= 500) { out.allowed = false; out.rule = "robots.txt unavailable (server error), treated as disallowed"; return out; }
  if (!r.ok) return out; // 4xx: no robots file, crawling allowed
  const groups: { agents: string[]; rules: [string, string][]; delay: number | null }[] = [];
  let cur: (typeof groups)[number] | null = null, lastWasAgent = false;
  for (const raw of (await r.text()).split(/\r?\n/)) {
    const line = raw.replace(/#.*/, "").trim();
    const m = line.match(/^([A-Za-z-]+)\s*:\s*(.*)$/);
    if (!m) continue;
    const key = m[1].toLowerCase(), val = m[2].trim();
    if (key === "user-agent") {
      if (!cur || !lastWasAgent) { cur = { agents: [], rules: [], delay: null }; groups.push(cur); }
      cur.agents.push(val.toLowerCase()); lastWasAgent = true; continue;
    }
    lastWasAgent = false;
    if (!cur) continue;
    if (key === "allow" || key === "disallow") cur.rules.push([key, val]);
    if (key === "crawl-delay" && Number(val) > 0) cur.delay = Number(val);
  }
  const mine = groups.filter((g) => g.agents.some((a) => a !== "*" && UA_TOKEN.toLowerCase().includes(a)));
  const use = mine.length ? mine : groups.filter((g) => g.agents.includes("*"));
  const rules = use.flatMap((g) => g.rules);
  out.crawl_delay_s = use.map((g) => g.delay).find((d) => d != null) ?? null;
  const toRe = (p: string) => new RegExp("^" + p.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\\\$$/, "$"));
  for (const path of PATHS) {
    let best: [string, string] | null = null;
    for (const [k, p] of rules) {
      if (!p) continue; // empty Disallow allows everything
      if (toRe(p).test(path) && (!best || p.length > best[1].length || (p.length === best[1].length && k === "allow"))) best = [k, p];
    }
    if (best?.[0] === "disallow") { out.allowed = false; out.rule = `Disallow: ${best[1]} (matches ${path})`; return out; }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Admins may run it any time; anyone else (the cron job uses the anon key)
  // at most once every 6 hours.
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: acc } = await caller.rpc("my_access");
  const isAdmin = acc?.role === "admin";
  if (!isAdmin) {
    const { data: last } = await svc.from("history_sync_log").select("ran_at").eq("source", "icca_bid_wins")
      .order("ran_at", { ascending: false }).limit(1).maybeSingle();
    if (last && Date.now() - new Date(last.ran_at).getTime() < 6 * 3600e3) return json({ ok: true, skipped: "ran recently" });
  }

  let robots: Robots | null = null;
  try {
    robots = await checkRobots();
    if (!robots.allowed) {
      const result = { skipped: "robots.txt disallows the feed", robots };
      await svc.from("history_sync_log").insert({ source: "icca_bid_wins", result, by_admin: isAdmin });
      return json({ ok: true, ...result });
    }
    const gap = Math.max(REQUEST_GAP_MS, (robots.crawl_delay_s ?? 0) * 1000);
    await sleep(gap);
    const cat = await fetch(`${WP}/categories?slug=bid-wins&_fields=id,count`, { headers: { "User-Agent": UA } }).then((r) => r.json());
    const catId = cat?.[0]?.id ?? 154;
    const posts: unknown[] = [];
    for (let page = 1; page <= 20; page++) {
      await sleep(gap);
      const r = await fetch(`${WP}/posts?categories=${catId}&per_page=100&page=${page}&orderby=date&order=desc&_fields=id,date,link,title,content,excerpt`,
        { headers: { "User-Agent": UA } });
      if (!r.ok) break;
      const batch = await r.json();
      for (const p of batch) {
        const text = strip(p.content?.rendered || "") || strip(p.excerpt?.rendered || "");
        posts.push({ id: p.id, date: String(p.date).slice(0, 10), link: p.link, title: strip(p.title?.rendered || ""), text: firstWords(text) });
      }
      const pages = Number(r.headers.get("X-WP-TotalPages") || "1");
      if (page >= pages) break;
    }
    const { data, error } = await svc.rpc("history_ingest_icca", { posts });
    const result = error ? { error: error.message, robots } : { ...data, fetched: posts.length, robots };
    await svc.from("history_sync_log").insert({ source: "icca_bid_wins", result, by_admin: isAdmin });
    return json(error ? { error: error.message } : { ok: true, ...result }, error ? 500 : 200);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await svc.from("history_sync_log").insert({ source: "icca_bid_wins", result: { error: msg, robots }, by_admin: isAdmin });
    return json({ error: msg }, 502);
  }
});
