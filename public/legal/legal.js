/* Shared legal helpers for the static pages (pipeline, partner and submit forms, /legal).
   Load /legal/config.js first: it defines window.LEGAL from legal.config.json, the same
   file the landing page footer reads. Legal text with versions comes from the
   legal_documents table through the public legal_document(type) RPC. */
(function () {
  const L = window.LEGAL || {};
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  /* Replaces {owner}, {product} and {year} with the configured values. */
  const fill = s => String(s ?? "").replace(/\{(owner|product|year)\}/g, (_, k) =>
    k === "owner" ? (L.owner || "") : k === "product" ? (L.product || "") : String(L.copyrightYear || ""));
  /* Plain text to HTML: blank-line paragraphs, and lines starting "1. " become an ordered list. */
  function html(body) {
    const lines = fill(body).split(/\r?\n/);
    let out = "", list = [], para = [];
    const flushPara = () => { if (para.length) { out += `<p>${esc(para.join(" "))}</p>`; para = []; } };
    const flushList = () => { if (list.length) { out += `<ol>${list.map(x => `<li>${esc(x)}</li>`).join("")}</ol>`; list = []; } };
    for (const raw of lines) {
      const line = raw.trim(), m = line.match(/^\d+\.\s+(.*)$/);
      if (m) { flushPara(); list.push(m[1]); }
      else if (!line) { flushPara(); flushList(); }
      else { flushList(); para.push(line); }
    }
    flushPara(); flushList();
    return out;
  }
  const link = k => L.links && L.links[k] ? `<a href="${esc(L.links[k].href)}">${esc(L.links[k].label)}</a>` : "";
  /* Footer notice (W7), legal links and the correction route (W11). */
  function footerHtml() {
    return `<div class="legalNotice">${esc(fill(L.footerNotice))}</div>
      <div class="legalLinks">${["terms", "notices"].map(link).join("")}<span>${esc(L.rightsPrompt || "")} <a href="${esc(L.links?.rights?.href || "/legal/rights")}">${esc(L.rightsLinkText || "")}</a></span></div>`;
  }
  function mountFooters() { document.querySelectorAll("[data-legal-footer]").forEach(el => { el.innerHTML = footerHtml(); }); }
  async function fetchDoc(sb, type) {
    const { data, error } = await sb.rpc("legal_document", { p_type: type });
    if (error || !data) throw new Error(error?.message || "not published");
    return data;
  }
  window.Legal = { config: L, esc, fill, html, footerHtml, mountFooters, fetchDoc };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mountFooters); else mountFooters();
})();
