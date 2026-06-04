import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const outputs = join(root, "outputs");

mkdirSync(outputs, { recursive: true });

const W = 1024;
const H = 1536;
const FONT = "sans-serif";

const colors = {
  bg: "#F3F4F8",
  card: "#FFFFFF",
  ink: "#101114",
  muted: "#7A7E87",
  faint: "#D9DCE3",
  blue: "#0A84FF",
  blueSoft: "#D8ECFF",
  green: "#30D158",
  greenSoft: "#DDF7E6",
  amber: "#C87400",
  amberSoft: "#FFF1D6",
  red: "#D8342A",
  redSoft: "#FFE1DE",
  purple: "#BF5AF2",
  neutralPill: "#E8E9EE",
  neutralText: "#666A73",
};

function esc(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function text(x, y, value, options = {}) {
  const {
    size = 28,
    weight = 400,
    color = colors.ink,
    anchor = "start",
    opacity = 1,
  } = options;
  return `<text x="${x}" y="${y}" font-family="${FONT}" font-size="${size}" font-weight="${weight}" fill="${color}" text-anchor="${anchor}" opacity="${opacity}">${esc(value)}</text>`;
}

function textLines(x, y, lines, options = {}) {
  const { size = 28, lineHeight = Math.round(size * 1.35) } = options;
  return lines
    .map((line, index) => text(x, y + index * lineHeight, line, { ...options, size }))
    .join("\n");
}

function wrap(value, maxChars, maxLines = 2) {
  const words = String(value).split(/\s+/);
  const lines = [];
  let current = "";
  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length <= maxChars) {
      current = next;
      continue;
    }
    if (current) {
      lines.push(current);
    }
    current = word;
    if (lines.length === maxLines) {
      break;
    }
  }
  if (current && lines.length < maxLines) {
    lines.push(current);
  }
  if (lines.length === maxLines && words.join(" ").length > lines.join(" ").length) {
    lines[maxLines - 1] = `${lines[maxLines - 1].replace(/[.,;:!?]*$/, "")}...`;
  }
  return lines;
}

function rect(x, y, width, height, options = {}) {
  const {
    fill = colors.card,
    stroke = "none",
    strokeWidth = 0,
    rx = 8,
    opacity = 1,
  } = options;
  return `<rect x="${x}" y="${y}" width="${width}" height="${height}" rx="${rx}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" opacity="${opacity}"/>`;
}

function circle(cx, cy, r, options = {}) {
  const { fill = colors.card, stroke = "none", strokeWidth = 0, opacity = 1 } = options;
  return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" opacity="${opacity}"/>`;
}

function line(x1, y1, x2, y2, options = {}) {
  const { stroke = colors.faint, strokeWidth = 2, opacity = 1, cap = "round" } = options;
  return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${stroke}" stroke-width="${strokeWidth}" opacity="${opacity}" stroke-linecap="${cap}"/>`;
}

function pill(x, y, label, options = {}) {
  const {
    fill = colors.neutralPill,
    color = colors.neutralText,
    icon = null,
    size = 25,
    weight = 700,
    height = 56,
    minWidth = 0,
    stroke = "none",
  } = options;
  const iconWidth = icon ? 24 : 0;
  const width = Math.max(minWidth, label.length * size * 0.54 + iconWidth + 42);
  const labelX = x + 22 + iconWidth;
  const parts = [rect(x, y, width, height, { fill, rx: height / 2, stroke, strokeWidth: stroke === "none" ? 0 : 2 })];
  if (icon) {
    parts.push(circle(x + 24, y + height / 2, 6, { fill: color }));
  }
  parts.push(text(labelX, y + height / 2 + size / 2 - 5, label, { size, weight, color }));
  return { width, svg: parts.join("\n") };
}

function badge(label, tone = "neutral") {
  const palette = {
    working: [colors.greenSoft, "#169A42"],
    action: [colors.amberSoft, colors.amber],
    error: [colors.redSoft, colors.red],
    neutral: [colors.neutralPill, colors.neutralText],
    blue: [colors.blueSoft, colors.blue],
  }[tone];
  return { label, fill: palette[0], color: palette[1] };
}

function statusBar() {
  return [
    text(104, 70, "6:47", { size: 40, weight: 700 }),
    rect(374, 28, 276, 68, { fill: "#000000", rx: 34 }),
    circle(758, 60, 5, { fill: "#A9ADB7" }),
    circle(778, 60, 5, { fill: "#A9ADB7" }),
    circle(798, 60, 5, { fill: "#A9ADB7" }),
    line(852, 62, 884, 62, { stroke: "#111111", strokeWidth: 7 }),
    line(860, 48, 876, 48, { stroke: "#111111", strokeWidth: 7 }),
    rect(910, 43, 62, 34, { fill: "none", stroke: "#111111", strokeWidth: 4, rx: 10 }),
    rect(916, 49, 46, 22, { fill: "#111111", rx: 6 }),
    rect(976, 54, 6, 14, { fill: "#111111", rx: 3 }),
  ].join("\n");
}

function base(title = "Dock") {
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`,
    rect(0, 0, W, H, { fill: colors.bg, rx: 0 }),
    statusBar(),
    text(44, 168, title, { size: 78, weight: 800 }),
  ];
}

function finish(parts) {
  return `${parts.join("\n")}\n</svg>\n`;
}

function iconButton(cx, cy, label, options = {}) {
  const { fill = "#FFFFFF", color = colors.blue, size = 34 } = options;
  return [
    circle(cx, cy, 48, { fill }),
    text(cx, cy + 12, label, { size, weight: 800, color, anchor: "middle" }),
  ].join("\n");
}

function rowCard(x, y, width, options) {
  const {
    rail = colors.blue,
    title,
    meta,
    summary,
    time = "now",
    badge: rowBadge = null,
    height = 170,
  } = options;
  const parts = [
    rect(x, y, width, height, { fill: colors.card, rx: 8 }),
    rect(x + 30, y + 28, 8, height - 56, { fill: rail, rx: 4 }),
  ];
  parts.push(text(x + 62, y + 52, title, { size: 32, weight: 760 }));
  if (rowBadge) {
    const b = pill(x + width - 38 - Math.max(150, rowBadge.label.length * 14), y + 26, rowBadge.label, {
      fill: rowBadge.fill,
      color: rowBadge.color,
      size: 22,
      height: 42,
      minWidth: Math.max(150, rowBadge.label.length * 14),
    });
    parts.push(b.svg);
  }
  parts.push(text(x + 62, y + 90, meta, { size: 25, color: colors.muted }));
  parts.push(textLines(x + 62, y + 126, wrap(summary, 54, 1), { size: 27, color: colors.ink, lineHeight: 35 }));
  parts.push(text(x + 62, y + height - 24, time, { size: 22, color: colors.muted }));
  parts.push(text(x + width - 38, y + height - 22, ">", { size: 34, weight: 700, color: colors.muted, anchor: "middle" }));
  return parts.join("\n");
}

function sectionTitle(y, title, detail) {
  return [
    text(44, y, title, { size: 28, weight: 800 }),
    detail ? text(44 + title.length * 16 + 24, y, detail, { size: 24, color: colors.muted, weight: 600 }) : "",
  ].join("\n");
}

function renderDockOverview() {
  const parts = base("Dock");
  parts.push(pill(588, 128, "Status labels", { fill: colors.neutralPill, color: colors.neutralText, size: 28, height: 66 }).svg);
  parts.push(iconButton(930, 162, "...", { fill: colors.bg, color: colors.blue }));
  parts.push(rect(44, 250, 936, 96, { fill: "#FFFFFF", rx: 8 }));
  parts.push(text(94, 312, "Search sessions, repo, branch, host", { size: 33, color: "#B7BAC2" }));
  parts.push(rect(44, 388, 238, 88, { fill: colors.blue, rx: 8 }));
  parts.push(text(163, 445, "Newest", { size: 35, weight: 800, color: "#FFFFFF", anchor: "middle" }));
  parts.push(rect(304, 388, 238, 88, { fill: colors.bg, stroke: "#D2D4DB", strokeWidth: 2, rx: 8 }));
  parts.push(text(423, 445, "Host", { size: 35, weight: 760, anchor: "middle" }));
  parts.push(rect(564, 388, 238, 88, { fill: colors.bg, stroke: "#D2D4DB", strokeWidth: 2, rx: 8 }));
  parts.push(text(683, 445, "Branch", { size: 35, weight: 760, anchor: "middle" }));
  parts.push(circle(900, 432, 66, { fill: colors.blueSoft }));
  parts.push(text(900, 443, "=", { size: 44, weight: 800, color: colors.blue, anchor: "middle" }));
  parts.push(text(44, 532, "1,241 shown · Existing list · row badges only", { size: 26, color: colors.muted }));

  parts.push(rowCard(44, 590, 936, {
    rail: "#FF9F0A",
    title: "Review relay restart",
    meta: "Amir-M5 · codex-client · main",
    summary: "Codex needs approval before restarting the relay service.",
    time: "2m ago",
    badge: badge("Needs approval", "action"),
    height: 150,
  }));
  parts.push(rowCard(44, 754, 936, {
    rail: "#FF9F0A",
    title: "Answer product copy question",
    meta: "Amir-M5 · codex-client · state-ux",
    summary: "Codex asked which label should appear in the thread header.",
    time: "5m ago",
    badge: badge("Needs answer", "action"),
    height: 150,
  }));
  parts.push(rowCard(44, 918, 936, {
    rail: colors.green,
    title: "Server thread renaming",
    meta: "Amir-M5 · freedom · codex-dock-agents-tab",
    summary: "Latest activity 8s ago. No user action needed.",
    time: "now",
    badge: badge("Codex is working", "working"),
    height: 150,
  }));
  parts.push(rowCard(44, 1082, 936, {
    rail: colors.red,
    title: "Thread state sync audit",
    meta: "Amir-M5 · codex-client · state-ux",
    summary: "Raw thread state is systemError. Badge only this thread.",
    time: "11m ago",
    badge: badge("Error", "error"),
    height: 150,
  }));
  parts.push(rowCard(44, 1246, 936, {
    rail: colors.faint,
    title: "Hand debugging",
    meta: "Amir-M5 · codex-client · main",
    summary: "Finished · Ready for next prompt. No Dock badge needed.",
    time: "18m ago",
    height: 150,
  }));

  return finish(parts);
}

function detailBase(navTitle = "Thread") {
  const parts = [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`,
    rect(0, 0, W, H, { fill: colors.bg, rx: 0 }),
    statusBar(),
    circle(96, 160, 58, { fill: "#FFFFFF" }),
    text(96, 180, "<", { size: 58, weight: 700, anchor: "middle" }),
    text(512, 176, navTitle, { size: 40, weight: 780, anchor: "middle" }),
    circle(928, 160, 58, { fill: "#FFFFFF" }),
    text(928, 176, "/", { size: 44, weight: 800, color: colors.blue, anchor: "middle" }),
  ];
  return parts;
}

function detailHeader(parts, config) {
  const {
    title,
    repo = "freedom · codex-dock-agents-tab",
    branch = "live-counts",
    statusLabel,
    statusTone,
    last = "019e908c-93cd-7e20-899e-eea5c66f7d32 · now",
  } = config;
  parts.push(rect(48, 250, 46, 46, { fill: "none", stroke: colors.blue, strokeWidth: 4, rx: 6 }));
  parts.push(text(114, 288, title, { size: 43, weight: 820 }));
  parts.push(textLines(114, 336, wrap(`${repo}-${branch}`, 34, 2), { size: 31, color: colors.muted, lineHeight: 38 }));
  const host = pill(44, 442, "Amir-M5", { fill: colors.blueSoft, color: colors.blue, size: 25, height: 56 });
  parts.push(host.svg);
  const st = badge(statusLabel, statusTone);
  parts.push(pill(44 + host.width + 20, 442, statusLabel, { fill: st.fill, color: st.color, size: 25, height: 56 }).svg);
  parts.push(text(44, 554, last, { size: 28, color: colors.muted }));
}

function composer(y, active = true) {
  const sendFill = active ? colors.blue : "#D9DCE3";
  return [
    rect(44, y, 560, 92, { fill: "#FFFFFF", rx: 8 }),
    text(78, y + 58, "Message Codex", { size: 31, color: "#B7BAC2" }),
    circle(680, y + 46, 48, { fill: colors.blueSoft }),
    text(680, y + 60, "mic", { size: 23, weight: 800, color: colors.blue, anchor: "middle" }),
    circle(808, y + 46, 48, { fill: colors.blueSoft }),
    text(808, y + 60, "dict", { size: 22, weight: 800, color: colors.blue, anchor: "middle" }),
    circle(936, y + 46, 48, { fill: sendFill }),
    text(936, y + 59, "send", { size: 20, weight: 800, color: active ? "#FFFFFF" : colors.muted, anchor: "middle" }),
  ].join("\n");
}

function messageCard(y, role, heading, body, tone = "working", height = 210) {
  const roleColor = tone === "error" ? colors.red : tone === "ready" ? colors.blue : "#24A148";
  const parts = [
    rect(44, y, 936, height, { fill: colors.card, rx: 8 }),
    text(80, y + 54, role, { size: 27, weight: 800, color: roleColor }),
    text(80, y + 98, heading, { size: 32, weight: 820 }),
    textLines(80, y + 144, wrap(body, 54, 4), { size: 28, color: colors.ink, lineHeight: 38 }),
  ];
  return parts.join("\n");
}

function renderThreadWorking() {
  const parts = detailBase();
  detailHeader(parts, {
    title: "Server thread renaming",
    statusLabel: "Codex is working",
    statusTone: "working",
  });
  parts.push(composer(618, false));
  parts.push(messageCard(756, "Agent", "Agent message", "I am reading the actual Codex thread state source and updating the canonical reference from that contract.", "working", 230));
  parts.push(messageCard(1016, "Agent", "Activity summary", "Command output is still streaming. No answer or approval is pending from you.", "working", 230));
  parts.push(rect(44, 1464, 936, 54, { fill: "#FFFFFF", rx: 8 }));
  parts.push(text(76, 1499, "State details", { size: 24, weight: 760, color: colors.muted }));
  parts.push(text(900, 1499, "hidden", { size: 24, weight: 760, color: colors.muted }));
  return finish(parts);
}

function renderThreadReady() {
  const parts = detailBase();
  detailHeader(parts, {
    title: "Rename threads",
    statusLabel: "Your turn · Ready",
    statusTone: "blue",
    last: "019e908c-93cd-7e20-899e-eea5c66f7d32 · 1m ago",
  });
  parts.push(composer(618, true));
  parts.push(messageCard(756, "Agent", "Done", "I updated the canonical reference and generated focused status mocks for Dock and Thread Detail.", "ready", 250));
  parts.push(messageCard(1040, "Agent", "No pending action", "This is the common full-permissions path: Codex is finished, and the next move is your prompt.", "ready", 230));
  parts.push(rect(44, 1492, 936, 54, { fill: "#FFFFFF", rx: 8 }));
  parts.push(text(76, 1527, "State details", { size: 24, weight: 760, color: colors.muted }));
  parts.push(text(858, 1527, "raw idle", { size: 24, weight: 760, color: colors.muted }));
  return finish(parts);
}

function renderThreadException() {
  const parts = detailBase();
  detailHeader(parts, {
    title: "Server thread renaming",
    statusLabel: "Error",
    statusTone: "error",
    last: "019e908c-93cd-7e20-899e-eea5c66f7d32 · 4m ago",
  });
  parts.push(composer(618, false));
  parts.push(messageCard(756, "Agent", "Last visible message", "I was checking the exact thread state contract and keeping raw error separate from turn state.", "working", 250));
  parts.push(rect(44, 1410, 936, 86, { fill: "#FFFFFF", rx: 8 }));
  parts.push(text(76, 1444, "State details", { size: 24, weight: 760, color: colors.muted }));
  parts.push(text(76, 1476, "Raw status: systemError.", { size: 22, color: colors.muted }));
  return finish(parts);
}

const files = [
  ["07-status-dock-overview.svg", renderDockOverview()],
  ["08-thread-detail-working.svg", renderThreadWorking()],
  ["09-thread-detail-ready.svg", renderThreadReady()],
  ["10-thread-detail-error.svg", renderThreadException()],
];

for (const [file, svg] of files) {
  writeFileSync(join(outputs, file), svg);
  console.log(join(outputs, file));
}
