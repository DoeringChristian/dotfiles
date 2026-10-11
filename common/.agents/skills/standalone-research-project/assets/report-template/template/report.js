let figures = [], active = 0, zoom = 1, panX = 0, panY = 0, pendingSelection = null, comments = [], saveTimer = null;
const $ = selector => document.querySelector(selector);
const el = (tag, className, text) => { const node = document.createElement(tag); if (className) node.className = className; if (text !== undefined) node.textContent = text; return node; };
const reportRoute = location.pathname.match(/^\/reports\/([a-z0-9][a-z0-9-]*)\//);
const commentsApi = reportRoute ? `/api/reports/${reportRoute[1]}/comments` : "/api/comments";
const commentsStorageKey = `standalone-report-comments:${reportRoute?.[1] || "main"}`;
const COMMENT_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4.5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-8l-5 3v-3H5a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2Z"/></svg>';
const isFigureTarget = target => target.startsWith("figure:");
function commentFor(target) { return [...comments].reverse().find(row => row.target === target); }
function commentIcon(target, line = "") { const button = el("button", "image-comment"); button.type = "button"; button.title = "Comment on image"; button.setAttribute("aria-label", "Comment on image"); button.innerHTML = COMMENT_ICON; button.onclick = event => { event.preventDefault(); event.stopPropagation(); openComment(target, line, "", button.getBoundingClientRect(), commentFor(target)); }; return button; }
async function plotSpec(figure) { if (!figure._spec) { const response = await fetch(figure.src); if (!response.ok) throw new Error(`Could not load ${figure.src}`); figure._spec = await response.json(); } return figure._spec; }
async function renderPlot(node, figure, full = false) { const spec = await plotSpec(figure); const layout = {...(spec.layout || {}), autosize: true}; const config = {responsive: true, displaylogo: false, ...(spec.config || {})};
  if (full) delete layout.height;
  else { layout.margin = {...(layout.margin || {}), t: Math.max(layout.margin?.t ?? 0, 48)}; Object.assign(config, {displayModeBar: false, scrollZoom: false}); } // Card preview: hover only; full tools live in the lightbox.
  await Plotly.react(node, spec.data || [], layout, config); }

Promise.all([fetch("report-data.json").then(r => r.json()), fetch("narrative.html").then(r => r.text())]).then(([data, narrative]) => {
  $("#title").textContent = data.project; $("#subtitle").textContent = data.subtitle;
  $("#status").textContent = data.status; $("#updated").textContent = `Updated · ${data.updated}`;
  data.summary.forEach((item, index) => { const card = el("article", "metric"); card.dataset.commentTarget = `metric:${index}`; card.append(el("span", null, item.label), el("strong", null, item.value), el("small", null, item.detail)); $("#summary").append(card); });
  data.findings.forEach(item => { const row = el("article", "finding"); row.id = item.id; row.dataset.commentTarget = `finding:${item.id}`; const body = el("div"); body.append(el("h3", null, item.title), el("p", null, item.body), el("small", null, `Source · ${item.source}`)); row.append(el("div", "state", item.state), body); $("#finding-list").append(row); });
  figures = data.figures.map(item => ({...item}));
  figures.forEach((item, index) => { const card = el("article", `figure-card comment-anchor${item.type === "plotly" ? " plotly-card" : ""}`); card.dataset.commentTarget = `figure:${item.id}`; const copy = el("div", "figure-copy"); copy.append(el("h3", null, item.title), el("p", null, item.caption)); if (item.type === "plotly") { const plot = el("div", "plotly-preview"); const expand = el("button", "figure-expand", "⛶"); expand.type = "button"; expand.title = "Open interactive figure"; expand.setAttribute("aria-label", "Open interactive figure"); expand.onclick = event => { event.stopPropagation(); openFigure(index); }; card.append(plot, copy, expand, commentIcon(`figure:${item.id}`, item.line || "")); renderPlot(plot, item); } else { card.tabIndex = 0; card.setAttribute("role", "button"); const image = el("img"); image.src = item.src; image.alt = item.title; card.append(image, copy, commentIcon(`figure:${item.id}`, item.line || "")); card.onclick = () => openFigure(index); card.onkeydown = event => { if (event.key === "Enter" || event.key === " ") openFigure(index); }; } $("#figure-grid").append(card); });
  data.next.forEach((item, index) => { const row = el("li", null, item); row.dataset.commentTarget = `next:${index}`; $("#next-list").append(row); });
  $("#report-prose").innerHTML = narrative;
  bindMarkdownImages(); bindSelectionComments(); loadComments();
});

const lightbox = $("#lightbox"), lightboxImage = $("#lightbox-image"), lightboxPlot = $("#lightbox-plot");
async function showFigure(index) { active = (index + figures.length) % figures.length; const figure = figures[active]; const interactive = figure.type === "plotly"; lightboxImage.hidden = interactive; lightboxPlot.hidden = !interactive; $(".zoom").hidden = interactive; if (interactive) { lightboxImage.src = ""; await renderPlot(lightboxPlot, figure, true); } else { if (globalThis.Plotly) Plotly.purge(lightboxPlot); lightboxImage.src = figure.src; lightboxImage.alt = figure.title; resetView(); } syncLightboxComment(); $("#lightbox-title").textContent = figure.title; $("#lightbox-caption").textContent = figure.caption || ""; }
function syncLightboxComment() { const button = $("#lightbox-comment"), figure = figures[active]; const has = Boolean(figure && commentFor(`figure:${figure.id}`)); button.classList.toggle("has-comment", has); button.title = has ? "Edit figure comment" : "Comment on figure"; }
function openFigure(index) { showFigure(index); lightbox.showModal(); }
function applyView() { lightboxImage.style.setProperty("--zoom", zoom); lightboxImage.style.setProperty("--pan-x", `${panX}px`); lightboxImage.style.setProperty("--pan-y", `${panY}px`); $("#zoom-label").textContent = `${Math.round(zoom * 100)}%`; }
let hoverPoint = null;
function imageCenter() { const parent = lightboxImage.offsetParent; if (!parent) { const rect = lightboxImage.getBoundingClientRect(); return {x: rect.left + rect.width / 2 - panX, y: rect.top + rect.height / 2 - panY}; } const box = parent.getBoundingClientRect(); return {x: box.left + lightboxImage.offsetLeft + lightboxImage.offsetWidth / 2, y: box.top + lightboxImage.offsetTop + lightboxImage.offsetHeight / 2}; }
// Zoom about `point` (client coordinates) so the pixel under it stays fixed; without a point, zoom about the current view.
function setZoom(value, point = null) { const next = Math.max(.5, Math.min(4, value)); if (next <= 1) { panX = 0; panY = 0; } else if (point) { const center = imageCenter(), ratio = next / zoom; panX = point.x - center.x - ratio * (point.x - center.x - panX); panY = point.y - center.y - ratio * (point.y - center.y - panY); } else { const ratio = next / zoom; panX *= ratio; panY *= ratio; } zoom = next; applyView(); }
function resetView() { zoom = 1; panX = 0; panY = 0; applyView(); }
lightbox.querySelector(".close").onclick = () => lightbox.close(); lightbox.querySelector(".previous").onclick = () => showFigure(active - 1); lightbox.querySelector(".next").onclick = () => showFigure(active + 1);
$("#lightbox-comment").onclick = event => { const figure = figures[active]; const anchor = event.currentTarget.getBoundingClientRect(); lightbox.close(); openComment(`figure:${figure.id}`, figure.line || "", "", anchor, commentFor(`figure:${figure.id}`)); };
lightbox.querySelector(".zoom").onclick = event => { const action = event.target.dataset.zoom; if (action === "in") setZoom(zoom + .25); if (action === "out") setZoom(zoom - .25); if (action === "reset") resetView(); };
lightboxImage.addEventListener("wheel", event => { event.preventDefault(); setZoom(zoom + (event.deltaY < 0 ? .15 : -.15), {x: event.clientX, y: event.clientY}); }, {passive: false});
lightboxImage.addEventListener("pointermove", event => { hoverPoint = {x: event.clientX, y: event.clientY}; });
lightboxImage.addEventListener("pointerleave", () => { hoverPoint = null; });
lightboxImage.draggable = false; lightboxImage.addEventListener("dragstart", event => event.preventDefault());
lightboxImage.addEventListener("pointerdown", event => { if (zoom <= 1) return; event.preventDefault(); const startX = event.clientX - panX, startY = event.clientY - panY; lightboxImage.setPointerCapture(event.pointerId); lightboxImage.classList.add("is-panning"); const move = next => { panX = next.clientX - startX; panY = next.clientY - startY; applyView(); }; const done = () => { lightboxImage.classList.remove("is-panning"); lightboxImage.removeEventListener("pointermove", move); lightboxImage.removeEventListener("pointerup", done); lightboxImage.removeEventListener("pointercancel", done); }; lightboxImage.addEventListener("pointermove", move); lightboxImage.addEventListener("pointerup", done); lightboxImage.addEventListener("pointercancel", done); });
document.addEventListener("keydown", event => { if (!lightbox.open) return; if (event.key === "ArrowLeft") showFigure(active - 1); if (event.key === "ArrowRight") showFigure(active + 1); if (event.key === "+" || event.key === "=") setZoom(zoom + .25, hoverPoint); if (event.key === "-") setZoom(zoom - .25, hoverPoint); if (event.key === "Escape") lightbox.close(); });

function bindMarkdownImages() {
  document.querySelectorAll("#report-prose img").forEach((image, offset) => {
    const line = image.closest("[data-source-line]")?.dataset.sourceLine || "unknown";
    const index = figures.push({id: `markdown-line-${line}-${offset}`, line, src: image.src, title: image.alt || `Figure from Markdown line ${line}`, caption: `Generated from report.md line ${line}`}) - 1;
    image.tabIndex = 0; image.setAttribute("role", "button"); image.onclick = () => openFigure(index); image.onkeydown = event => { if (event.key === "Enter" || event.key === " ") openFigure(index); }; const anchor = image.closest("[data-source-line]") || image.parentElement; anchor.classList.add("comment-anchor"); anchor.dataset.commentTarget = `figure:markdown-line-${line}-${offset}`; anchor.append(commentIcon(`figure:markdown-line-${line}-${offset}`, line));
  });
}

const commentPopover = $("#comment-popover"), commentForm = $("#comment-form");
function placeCommentPopover(rect) { const width = 360, gap = 8; const left = Math.max(12, Math.min(window.innerWidth - width - 12, rect?.left ?? (window.innerWidth - width) / 2)); const top = Math.max(12, Math.min(window.innerHeight - 230, (rect?.bottom ?? window.innerHeight / 2) + gap)); commentPopover.style.left = `${left}px`; commentPopover.style.top = `${top}px`; }
function closeComment() { if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; void saveComment(); } commentPopover.hidden = true; }
function openComment(target, line = "", quote = "", anchor = null, existing = null) { clearTimeout(saveTimer); if (!existing && isFigureTarget(target)) existing = commentFor(target); if (existing) { line = existing.line || line; quote = existing.quote || quote; } commentForm.elements.id.value = existing?.id || ""; commentForm.elements.target.value = target; commentForm.elements.line.value = line; commentForm.elements.quote.value = quote; commentForm.elements.text.value = existing?.text || ""; $("#comment-target").textContent = line ? `report.md line ${line}` : target; $("#comment-quote").textContent = quote; $("#comment-quote").hidden = !quote; $("#comment-message").textContent = existing ? "Saved" : "Autosaves while you type"; placeCommentPopover(anchor); commentPopover.hidden = false; commentForm.elements.text.focus(); }
function bindSelectionComments() {
  const report = $("main"), button = $("#selection-comment");
  const inspect = () => { const selection = window.getSelection(); const quote = selection?.toString().trim(); if (!quote || !selection.rangeCount || commentPopover.contains(selection.anchorNode)) { button.hidden = true; return; } const node = selection.anchorNode?.nodeType === Node.TEXT_NODE ? selection.anchorNode.parentElement : selection.anchorNode; if (!node || !report.contains(node)) { button.hidden = true; return; } const block = node.closest("[data-source-line]"); const context = block || node.closest("[data-comment-target]") || node.closest("section") || node.closest("header, footer") || report; const line = block?.dataset.sourceLine || ""; const target = line ? `markdown:line:${line}` : context.dataset.commentTarget || (context.id ? `section:${context.id}` : "section:report"); const rect = selection.getRangeAt(0).getBoundingClientRect(); const formula = node.closest(".math-tex"); pendingSelection = {line, target, quote: (formula ? `$${formula.dataset.latex}$` : quote).slice(0, 1000), rect}; button.style.left = `${Math.max(8, Math.min(window.innerWidth - 40, rect.right + 6))}px`; button.style.top = `${Math.max(8, Math.min(window.innerHeight - 40, rect.bottom + 6))}px`; button.hidden = false; };
  report.addEventListener("mouseup", () => setTimeout(inspect));
  report.addEventListener("touchend", () => setTimeout(inspect));
  report.addEventListener("keyup", event => { if (event.shiftKey) setTimeout(inspect); });
  button.onclick = () => { button.hidden = true; openComment(pendingSelection.target, pendingSelection.line, pendingSelection.quote, pendingSelection.rect); };
}

function localComments() { return JSON.parse(localStorage.getItem(commentsStorageKey) || "[]"); }
function upsert(rows, comment) { const index = rows.findIndex(row => row.id === comment.id); if (index < 0) rows.push(comment); else rows[index] = comment; return rows; }
function storeLocal(comment) { localStorage.setItem(commentsStorageKey, JSON.stringify(upsert(localComments(), comment))); }
function anchorFor(target) { if (target.startsWith("section:")) return document.getElementById(target.slice(8)); if (target.startsWith("finding:")) return document.getElementById(target.slice(8)); if (target.startsWith("markdown:line:")) return document.querySelector(`[data-source-line="${target.slice(14)}"]`); return [...document.querySelectorAll("[data-comment-target]")].find(node => node.dataset.commentTarget === target); }
function clearCommentMarks() {
  document.querySelectorAll(".comment-bubble").forEach(node => node.remove());
  document.querySelectorAll("mark.comment-highlight").forEach(mark => { const parent = mark.parentNode; mark.replaceWith(...mark.childNodes); parent.normalize(); });
  document.querySelectorAll(".has-comment").forEach(node => node.classList.remove("has-comment"));
  document.querySelectorAll(".math-highlight").forEach(node => { node.classList.remove("math-highlight"); node.onclick = null; node.removeAttribute("title"); });
}
function highlightQuote(root, quote) {
  const needle = quote.replace(/\s+/g, " ").trim(); if (!needle) return [];
  const formula = [...root.querySelectorAll(".math-tex")].find(node => `$${node.dataset.latex}$` === needle);
  if (formula) { formula.classList.add("math-highlight"); return [formula]; }
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {acceptNode: node => node.parentElement.closest("button, math, .comment-popover") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT});
  let text = ""; const map = []; let node;
  while ((node = walker.nextNode())) { const value = node.nodeValue; for (let i = 0; i < value.length; i++) { const space = /\s/.test(value[i]); if (space && (!text || text.endsWith(" "))) continue; text += space ? " " : value[i]; map.push([node, i]); } }
  const start = text.indexOf(needle); if (start < 0) return [];
  const spans = new Map(); for (let k = start; k < start + needle.length; k++) { const [textNode, offset] = map[k]; const span = spans.get(textNode); if (span) span[1] = offset + 1; else spans.set(textNode, [offset, offset + 1]); }
  return [...spans].map(([textNode, [from, to]]) => { const range = document.createRange(); range.setStart(textNode, from); range.setEnd(textNode, to); const mark = el("mark", "comment-highlight"); range.surroundContents(mark); return mark; });
}
function renderCommentBubbles() {
  clearCommentMarks();
  const blockLevel = new Map();
  comments.forEach(row => {
    const anchor = anchorFor(row.target); if (!anchor) return;
    const open = event => { if (window.getSelection()?.toString().trim()) return; event.preventDefault(); event.stopPropagation(); openComment(row.target, row.line || "", row.quote || "", event.currentTarget.getBoundingClientRect(), row); };
    if (isFigureTarget(row.target)) { anchor.classList.add("has-comment"); anchor.querySelectorAll(":scope > .image-comment").forEach(button => { button.classList.add("has-comment"); button.title = "Edit figure comment"; }); return; }
    const marks = row.quote ? highlightQuote(anchor, row.quote) : [];
    if (marks.length) { marks.forEach(mark => { mark.title = row.text; mark.onclick = open; }); const bubble = el("button", "comment-bubble inline"); bubble.type = "button"; bubble.title = row.text; bubble.setAttribute("aria-label", "Open comment"); bubble.innerHTML = COMMENT_ICON; bubble.onclick = open; marks.at(-1).after(bubble); return; }
    if (!blockLevel.has(anchor)) blockLevel.set(anchor, []); blockLevel.get(anchor).push({row, open, stale: Boolean(row.quote)});
  });
  blockLevel.forEach((entries, anchor) => { const {open} = entries.at(-1); const stale = entries.some(entry => entry.stale); anchor.classList.add("comment-anchor", "has-comment"); const bubble = el("button", `comment-bubble${stale ? " is-stale" : ""}`, entries.length > 1 ? String(entries.length) : ""); bubble.type = "button"; if (entries.length === 1) bubble.innerHTML = COMMENT_ICON; bubble.title = stale ? "Quoted text no longer found; open comment" : entries.length > 1 ? `${entries.length} comments` : "Open comment"; bubble.onclick = open; anchor.append(bubble); });
  syncLightboxComment();
}
async function loadComments() { let hosted = []; try { const response = await fetch(commentsApi); if (response.ok) hosted = await response.json(); } catch (_) {} comments = [...hosted]; localComments().forEach(row => upsert(comments, row)); comments = comments.filter(row => row.event !== "resolve" && row.target); renderCommentBubbles(); }
async function saveComment() {
  const payload = Object.fromEntries(new FormData(commentForm));
  payload.text = payload.text.trim();
  if (!payload.text) { $("#comment-message").textContent = "Autosaves while you type"; return; }
  $("#comment-message").textContent = "Saving…";
  try { const response = await fetch(commentsApi, {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(payload)}); if (!response.ok) throw new Error("server rejected comment"); const saved = await response.json(); commentForm.elements.id.value = saved.id; upsert(comments, saved); }
  catch (_) { const id = payload.id || globalThis.crypto?.randomUUID?.() || `local-${Date.now()}-${Math.random().toString(16).slice(2)}`; const saved = {...payload, id, timestamp: new Date().toISOString(), storage: "browser"}; commentForm.elements.id.value = id; storeLocal(saved); upsert(comments, saved); }
  $("#comment-message").textContent = "Saved"; renderCommentBubbles();
}
commentForm.addEventListener("submit", event => event.preventDefault());
commentForm.elements.text.addEventListener("input", () => { clearTimeout(saveTimer); $("#comment-message").textContent = "Saving…"; saveTimer = setTimeout(() => { saveTimer = null; void saveComment(); }, 500); });
document.addEventListener("pointerdown", event => { if (!commentPopover.hidden && !commentPopover.contains(event.target) && !event.target.closest(".comment-bubble, .image-comment, #selection-comment")) closeComment(); });
document.addEventListener("keydown", event => { if (event.key === "Escape" && !commentPopover.hidden) closeComment(); });

const AGENT_INSTRUCTIONS = `Please address these report comments.
For each comment: locate its quote first, falling back to its line or target. Make the requested change, or ask me if its consequence is ambiguous. Then rebuild with \`pixi run report-build\`.
Append comments marked "storage": "browser" to reports/knowledge/comments.jsonl first. Record each resolution by appending {"id": "<comment id>", "event": "resolve", "timestamp": "<ISO time>", "resolution": "<what changed>"} to that file. Never edit or delete existing lines.
Afterwards, summarize what changed in the code, the runs, the findings, and the report.`;
async function copyText(text) {
  try { await navigator.clipboard.writeText(text); return true; } catch (_) {}
  const area = el("textarea"); area.value = text; area.setAttribute("readonly", ""); area.style.position = "fixed"; area.style.opacity = "0"; document.body.append(area); area.select();
  const copied = document.execCommand("copy"); area.remove(); return copied;
}
function flashTip(button, text) {
  button.dataset.tooltip = text; button.classList.add("show-tip"); clearTimeout(button._tipTimer);
  button._tipTimer = setTimeout(() => { button.dataset.tooltip = button.getAttribute("aria-label"); button.classList.remove("show-tip"); }, 1600);
}
const plural = count => `${count} comment${count === 1 ? "" : "s"}`;
$("#copy-comments").onclick = async event => {
  const button = event.currentTarget;
  await loadComments();
  const open = comments.map(({id, target, line, quote, text, storage}) => ({id, target, line: line || null, quote: quote || null, text, ...(storage ? {storage} : {})}));
  if (!open.length) { flashTip(button, "No open comments"); return; }
  const copied = await copyText(`${AGENT_INSTRUCTIONS}\n\nOpen comments (${open.length}):\n${JSON.stringify(open, null, 2)}\n`);
  flashTip(button, copied ? `Copied ${plural(open.length)}` : "Copy failed");
};

// Clearing appends resolve events; the comment history itself is never erased.
const clearConfirm = $("#clear-confirm");
function closeClearConfirm() { clearConfirm.hidden = true; $("#clear-comments").setAttribute("aria-expanded", "false"); }
$("#clear-comments").onclick = async event => {
  const button = event.currentTarget;
  if (!clearConfirm.hidden) { closeClearConfirm(); return; }
  await loadComments();
  if (!comments.length) { flashTip(button, "No open comments"); return; }
  $("#clear-confirm-text").textContent = `Clear ${plural(comments.length)}? They stay in the comment history.`;
  const rect = button.getBoundingClientRect();
  clearConfirm.style.left = `${Math.max(12, Math.min(window.innerWidth - 252, rect.left))}px`; clearConfirm.style.top = `${rect.bottom + 8}px`;
  clearConfirm.hidden = false; button.setAttribute("aria-expanded", "true"); clearConfirm.querySelector('[data-confirm="cancel"]').focus();
};
clearConfirm.onclick = async event => {
  const action = event.target.closest("[data-confirm]")?.dataset.confirm; if (!action) return;
  closeClearConfirm(); if (action !== "clear") return;
  const button = $("#clear-comments"), count = comments.length, hosted = comments.some(row => row.storage !== "browser");
  if (hosted) { try { const response = await fetch(`${commentsApi}/clear`, {method: "POST", headers: {"Content-Type": "application/json"}, body: "{}"}); if (!response.ok) throw new Error("clear rejected"); } catch (_) { flashTip(button, "Clear failed"); return; } }
  localStorage.removeItem(commentsStorageKey); closeComment(); await loadComments();
  flashTip(button, `Cleared ${plural(count)}`);
};
document.addEventListener("pointerdown", event => { if (!clearConfirm.hidden && !clearConfirm.contains(event.target) && !event.target.closest("#clear-comments")) closeClearConfirm(); });
document.addEventListener("keydown", event => { if (event.key === "Escape" && !clearConfirm.hidden) closeClearConfirm(); });
