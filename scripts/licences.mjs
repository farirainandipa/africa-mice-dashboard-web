// IP website change W10: open-source licence check and third-party notices page.
//
// Runs after `vite build` (see package.json). It reads every package in
// package-lock.json, fails the build if any licence is outside the allow-list,
// and writes dist/legal/third-party-notices.html, linked from every footer.
// `node scripts/licences.mjs --check` checks without writing the page.
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const CHECK_ONLY = process.argv.includes('--check');

/** Licences any dependency may use. */
const ALLOWED = new Set(['MIT', 'ISC', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', '0BSD', 'CC0-1.0', 'BlueOak-1.0.0', 'Unlicense']);
/** Weak copyleft, accepted for build tools only (never shipped to the browser). */
const BUILD_ONLY = new Set(['MPL-2.0']);

/** Code and fonts the pages load from a CDN at run time. Keep in step with the <script> and font tags. */
const BROWSER_ASSETS = [
  { name: '@supabase/supabase-js', version: '2.45.4', license: 'MIT', url: 'https://github.com/supabase/supabase-js', use: 'Pipeline, admin and legal pages (loaded from cdn.jsdelivr.net)' },
  { name: 'Manrope typeface', version: 'Google Fonts', license: 'OFL-1.1', url: 'https://github.com/sharanda/manrope', use: 'All pages (loaded from fonts.googleapis.com)' },
];
const ASSET_ALLOWED = new Set([...ALLOWED, 'OFL-1.1']);

/** True when an SPDX expression is satisfied by the allowed set. */
function allowed(expr, set) {
  const e = String(expr || '').replace(/[()]/g, ' ').trim();
  if (!e) return false;
  if (/\sOR\s/i.test(e)) return e.split(/\s+OR\s+/i).some((x) => allowed(x, set));
  if (/\sAND\s/i.test(e)) return e.split(/\s+AND\s+/i).every((x) => allowed(x, set));
  return set.has(e.replace(/\+$/, ''));
}

const lock = JSON.parse(readFileSync(join(root, 'package-lock.json'), 'utf8'));
const pkgs = Object.entries(lock.packages)
  .filter(([path]) => path.startsWith('node_modules/'))
  .map(([path, p]) => ({ path, name: path.slice(path.lastIndexOf('node_modules/') + 13), version: p.version, license: p.license || '', dev: !!p.dev, optional: !!p.optional }));

const problems = [];
for (const p of pkgs) {
  const ok = allowed(p.license, ALLOWED) || (p.dev && allowed(p.license, new Set([...ALLOWED, ...BUILD_ONLY])));
  if (!ok) problems.push(`${p.name}@${p.version}: ${p.license || 'no licence declared'}${p.dev ? ' (build tool)' : ' (shipped)'}`);
}
for (const a of BROWSER_ASSETS) if (!allowed(a.license, ASSET_ALLOWED)) problems.push(`${a.name}: ${a.license} (browser asset)`);

if (problems.length) {
  console.error(`Licence check failed. These licences are not on the allow-list in scripts/licences.mjs:\n  ${problems.join('\n  ')}`);
  process.exit(1);
}
console.log(`Licence check passed for ${pkgs.length} packages and ${BROWSER_ASSETS.length} browser assets.`);
if (CHECK_ONLY) process.exit(0);

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
function licenceText(path) {
  const dir = join(root, path);
  if (!existsSync(dir)) return '';
  const f = readdirSync(dir).find((n) => /^(licen[cs]e|copying)(\.|$)/i.test(n));
  return f ? readFileSync(join(dir, f), 'utf8').trim() : '';
}

const shipped = pkgs.filter((p) => !p.dev && !p.name.startsWith('@types/')).sort((a, b) => a.name.localeCompare(b.name));
const tools = pkgs.filter((p) => p.dev || p.name.startsWith('@types/')).sort((a, b) => a.name.localeCompare(b.name));
const legal = JSON.parse(readFileSync(join(root, 'legal.config.json'), 'utf8'));
const notice = legal.footerNotice.replaceAll('{owner}', legal.owner).replaceAll('{product}', legal.product).replaceAll('{year}', String(legal.copyrightYear));

const html = `<!DOCTYPE html>
<html lang="en-GB">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Third-party notices · ${esc(legal.product)}</title>
<meta name="description" content="Open-source software and fonts used by the ${esc(legal.product)}, with their licences.">
<link rel="icon" type="image/svg+xml" href="/favicon.svg?v=3">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/pipeline/theme.css">
<style>
.doc{max-width:860px}
.doc h1{font-size:30px;font-weight:800;letter-spacing:-.02em;margin:10px 0 6px}
.doc h2{font-size:18px;font-weight:700;margin:34px 0 10px}
table.lic{width:100%;border-collapse:collapse;font-size:13px}
table.lic th,table.lic td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
table.lic th{font-size:10.5px;text-transform:uppercase;letter-spacing:.12em;color:var(--faint)}
details{margin:6px 0}
details pre{white-space:pre-wrap;font-size:11.5px;color:var(--muted);background:var(--panel2);padding:12px;border-radius:8px;max-height:320px;overflow:auto}
</style>
</head>
<body>
<main class="page"><div class="wrap"><div class="doc">
<p class="overline">Legal</p>
<h1>Third-party notices</h1>
<p class="sub">The ${esc(legal.product)} is built with the open-source software and fonts below. Each remains the property of its authors and is used under the licence shown. This page is generated from the project's lockfile at every build.</p>

<h2>Shipped in the landing page</h2>
<table class="lic"><thead><tr><th>Package</th><th>Version</th><th>Licence</th></tr></thead><tbody>
${shipped.map((p) => { const t = licenceText(p.path); return `<tr><td>${esc(p.name)}${t ? `<details><summary>Licence text</summary><pre>${esc(t)}</pre></details>` : ''}</td><td>${esc(p.version)}</td><td>${esc(p.license)}</td></tr>`; }).join('\n')}
</tbody></table>

<h2>Loaded by the pages from a CDN</h2>
<table class="lic"><thead><tr><th>Component</th><th>Version</th><th>Licence</th><th>Used by</th></tr></thead><tbody>
${BROWSER_ASSETS.map((a) => `<tr><td><a href="${esc(a.url)}" rel="noopener">${esc(a.name)}</a></td><td>${esc(a.version)}</td><td>${esc(a.license)}</td><td>${esc(a.use)}</td></tr>`).join('\n')}
</tbody></table>

<h2>Used to build the site (not shipped)</h2>
<table class="lic"><thead><tr><th>Package</th><th>Version</th><th>Licence</th></tr></thead><tbody>
${tools.map((p) => `<tr><td>${esc(p.name)}</td><td>${esc(p.version)}</td><td>${esc(p.license)}</td></tr>`).join('\n')}
</tbody></table>
<p class="sub" style="margin-top:28px"><a href="/legal?doc=terms_of_access">Terms of Access</a> · <a href="/">Home</a></p>
</div></div></main>
<footer class="siteFoot"><div class="in"><span>${esc(notice)}</span></div></footer>
</body>
</html>
`;
mkdirSync(join(root, 'dist', 'legal'), { recursive: true });
writeFileSync(join(root, 'dist', 'legal', 'third-party-notices.html'), html);
console.log(`Wrote dist/legal/third-party-notices.html (${shipped.length} shipped, ${tools.length} build tools).`);
