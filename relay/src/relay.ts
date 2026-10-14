/**
 * FormCoach beta sign-up relay (Cloudflare Worker).
 *
 * POST /signup  {name, email, plan, trial_months, sport?, notes?, website?}
 *   -> emails the owner (env.OWNER_EMAIL) via Resend.
 *
 * The static GitHub Pages site cannot hold the Resend API key, so it posts here.
 * This relay NEVER accepts payment card data; payments use the hosted checkout.
 */

export interface KVLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

export interface Env {
  RESEND_API_KEY?: string;
  OWNER_EMAIL?: string;
  FROM_EMAIL?: string;
  ALLOWED_ORIGINS?: string;
  SEND_CONFIRMATION?: string;
  SIGNUPS?: KVLike;
}

export const DEFAULT_ALLOWED_ORIGINS = [
  "https://bryanzhao08.github.io",
  "http://localhost:5173",
  "http://localhost:4317",
];
export const DEFAULT_FROM = "FormCoach Beta <onboarding@resend.dev>";
export const RESEND_URL = "https://api.resend.com/emails";
export const CARD_ERROR =
  "Card details are never collected here; payments go through the hosted checkout.";
export const RATE_LIMIT = 5;
export const RATE_WINDOW_SECONDS = 3600;

const PLANS = ["monthly", "annual", "lifetime"] as const;
export type Plan = (typeof PLANS)[number];

export interface Signup {
  name: string;
  email: string;
  plan: Plan;
  trial_months: number;
  sport?: string;
  notes?: string;
}

// ---------------------------------------------------------------- origins / CORS

export function allowedOrigins(env: Env): string[] {
  const raw = env.ALLOWED_ORIGINS?.trim();
  if (!raw) return DEFAULT_ALLOWED_ORIGINS;
  return raw
    .split(",")
    .map((s) => s.trim().replace(/\/+$/, ""))
    .filter(Boolean);
}

export function isAllowedOrigin(origin: string | null, env: Env): boolean {
  if (!origin) return false;
  return allowedOrigins(env).includes(origin.replace(/\/+$/, ""));
}

function corsHeaders(origin: string | null, env: Env): Record<string, string> {
  const h: Record<string, string> = { Vary: "Origin" };
  if (origin && isAllowedOrigin(origin, env)) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    h["Access-Control-Allow-Headers"] = "Content-Type";
    h["Access-Control-Max-Age"] = "86400";
  }
  return h;
}

function json(body: unknown, status: number, extra: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...extra },
  });
}

// ---------------------------------------------------------------- card-data guard

const CARD_KEYS = new Set([
  "card", "cc", "cvv", "cvc", "cvv2", "cvc2", "pan", "expiry", "exp", "exp_month",
  "exp_year", "expiration", "ccnum", "ccnumber", "cardnumber", "card_number",
  "securitycode", "security_code",
]);
// 13-19 digits, optionally grouped with single spaces or dashes (e.g. "4242 4242 4242 4242").
const CARD_NUMBER_RE = /(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)/;

function isCardKey(key: string): boolean {
  const k = key.toLowerCase().replace(/[^a-z0-9_]/g, "");
  if (CARD_KEYS.has(k) || CARD_KEYS.has(k.replace(/_/g, ""))) return true;
  return /card|cvv|cvc|expiry/.test(k);
}

/** True if the value (recursively) looks like it contains payment card data. */
export function containsCardData(value: unknown, depth = 0): boolean {
  if (depth > 10) return true; // absurd nesting; refuse rather than inspect
  if (typeof value === "string") return CARD_NUMBER_RE.test(value);
  if (typeof value === "number" || typeof value === "bigint") {
    return CARD_NUMBER_RE.test(String(value));
  }
  if (Array.isArray(value)) return value.some((v) => containsCardData(v, depth + 1));
  if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (isCardKey(k) || CARD_NUMBER_RE.test(k)) return true;
      if (containsCardData(v, depth + 1)) return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------- validation

const EMAIL_RE =
  /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
// Control chars (incl. CR/LF, which matter for header injection in the subject line).
const CONTROL_RE = /[\u0000-\u001f\u007f]/;

export type ValidationResult = { ok: true; value: Signup } | { ok: false; error: string };

export function validateSignup(body: unknown): ValidationResult {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, error: "Body must be a JSON object." };
  }
  const b = body as Record<string, unknown>;

  if (typeof b.name !== "string") return { ok: false, error: "name is required." };
  const name = b.name.trim();
  if (!name || name.length > 80 || CONTROL_RE.test(name)) {
    return { ok: false, error: "name must be 1-80 characters." };
  }

  if (typeof b.email !== "string") return { ok: false, error: "email is required." };
  const email = b.email.trim();
  if (email.length > 120 || !EMAIL_RE.test(email) || email.split("@")[0].length > 64) {
    return { ok: false, error: "email is not valid." };
  }

  if (typeof b.plan !== "string" || !(PLANS as readonly string[]).includes(b.plan)) {
    return { ok: false, error: "plan must be monthly, annual or lifetime." };
  }

  const tm = b.trial_months;
  if (typeof tm !== "number" || !Number.isInteger(tm) || tm < 0 || tm > 12) {
    return { ok: false, error: "trial_months must be an integer from 0 to 12." };
  }

  const out: Signup = { name, email, plan: b.plan as Plan, trial_months: tm };

  if (b.sport !== undefined && b.sport !== null && b.sport !== "") {
    if (typeof b.sport !== "string") return { ok: false, error: "sport must be text." };
    const sport = b.sport.trim();
    if (sport.length > 60 || CONTROL_RE.test(sport)) {
      return { ok: false, error: "sport must be at most 60 characters." };
    }
    if (sport) out.sport = sport;
  }

  if (b.notes !== undefined && b.notes !== null && b.notes !== "") {
    if (typeof b.notes !== "string") return { ok: false, error: "notes must be text." };
    const notes = b.notes.trim();
    if (notes.length > 500) return { ok: false, error: "notes must be at most 500 characters." };
    if (notes) out.notes = notes;
  }

  return { ok: true, value: out };
}

// ---------------------------------------------------------------- rate limiting

const memoryBuckets = new Map<string, { count: number; resetAt: number }>();

/** Test hook. */
export function _resetMemoryRateLimit(): void {
  memoryBuckets.clear();
}

/** Returns true if this request is allowed (and records it). */
export async function checkRateLimit(ip: string, env: Env, now = Date.now()): Promise<boolean> {
  const bucket = Math.floor(now / 1000 / RATE_WINDOW_SECONDS);
  const key = `rl:${ip}:${bucket}`;

  if (env.SIGNUPS) {
    try {
      const current = parseInt((await env.SIGNUPS.get(key)) ?? "0", 10) || 0;
      if (current >= RATE_LIMIT) return false;
      await env.SIGNUPS.put(key, String(current + 1), {
        expirationTtl: RATE_WINDOW_SECONDS + 60,
      });
      return true;
    } catch {
      // KV hiccup: fall through to in-memory best effort.
    }
  }

  // Best effort: only per-isolate, resets whenever Cloudflare recycles the isolate.
  if (memoryBuckets.size > 5000) {
    for (const [k, v] of memoryBuckets) if (v.resetAt <= now) memoryBuckets.delete(k);
  }
  const entry = memoryBuckets.get(key);
  if (!entry || entry.resetAt <= now) {
    memoryBuckets.set(key, { count: 1, resetAt: (bucket + 1) * RATE_WINDOW_SECONDS * 1000 });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count += 1;
  return true;
}

// ---------------------------------------------------------------- email

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export interface Meta {
  timestamp: string;
  country: string;
  userAgent: string;
  origin: string;
}

export function buildOwnerEmail(s: Signup, meta: Meta) {
  const rows: [string, string][] = [
    ["Name", s.name],
    ["Email", s.email],
    ["Plan", s.plan],
    ["Free trial (months)", String(s.trial_months)],
    ["Trial starts", meta.timestamp],
    ["Sport", s.sport ?? "-"],
    ["Notes", s.notes ?? "-"],
    ["Received", meta.timestamp],
    ["Country", meta.country],
    ["User agent", meta.userAgent],
    ["Origin", meta.origin],
  ];
  const subject = `New FormCoach beta sign-up: ${s.plan}`;
  const text =
    "New FormCoach beta sign-up\n\n" + rows.map(([k, v]) => `${k}: ${v}`).join("\n") + "\n";
  const html =
    `<h2>New FormCoach beta sign-up</h2>` +
    `<table cellpadding="4" style="border-collapse:collapse;font-family:sans-serif">` +
    rows
      .map(
        ([k, v]) =>
          `<tr><th align="left" style="vertical-align:top">${escapeHtml(k)}</th>` +
          `<td style="white-space:pre-wrap">${escapeHtml(v)}</td></tr>`,
      )
      .join("") +
    `</table>`;
  return { subject, text, html };
}

export function buildConfirmationEmail(s: Signup) {
  const subject = "You're on the FormCoach beta list";
  const trial =
    s.trial_months > 0
      ? `Your ${s.trial_months}-month free trial of the ${s.plan} plan starts when we open the beta to you.`
      : `You picked the ${s.plan} plan.`;
  const text =
    `Hi ${s.name},\n\nThanks for signing up for the FormCoach beta. ${trial}\n\n` +
    `We'll email you when your access is ready. No payment details are needed for the beta.\n\n- FormCoach\n`;
  const html =
    `<p>Hi ${escapeHtml(s.name)},</p><p>Thanks for signing up for the FormCoach beta. ${escapeHtml(trial)}</p>` +
    `<p>We'll email you when your access is ready. No payment details are needed for the beta.</p><p>- FormCoach</p>`;
  return { subject, text, html };
}

async function sendResend(
  env: Env,
  payload: Record<string, unknown>,
): Promise<{ ok: boolean; status: number }> {
  const res = await fetch(RESEND_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  return { ok: res.ok, status: res.status };
}

// ---------------------------------------------------------------- handler

const MAX_BODY_BYTES = 8 * 1024;

export async function handleRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const origin = request.headers.get("Origin");
  const cors = corsHeaders(origin, env);

  if (url.pathname !== "/signup") {
    return json({ ok: false, error: "Not found." }, 404, cors);
  }

  if (request.method === "OPTIONS") {
    if (!isAllowedOrigin(origin, env)) return new Response(null, { status: 403, headers: cors });
    return new Response(null, { status: 204, headers: cors });
  }

  if (request.method !== "POST") {
    return json({ ok: false, error: "Method not allowed." }, 405, { ...cors, Allow: "POST, OPTIONS" });
  }

  if (!isAllowedOrigin(origin, env)) {
    return json({ ok: false, error: "Origin not allowed." }, 403, cors);
  }

  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) {
    return json({ ok: false, error: "Request too large." }, 413, cors);
  }
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ ok: false, error: "Body must be valid JSON." }, 400, cors);
  }

  // Card data check comes first so it can never reach logs or email.
  if (containsCardData(body)) {
    return json({ ok: false, error: CARD_ERROR }, 400, cors);
  }

  // Honeypot: real users never fill the hidden "website" field. Pretend success.
  if (body && typeof body === "object" && !Array.isArray(body)) {
    const hp = (body as Record<string, unknown>).website;
    if (hp !== undefined && hp !== null && String(hp).trim() !== "") {
      return json({ ok: true }, 200, cors);
    }
  }

  const v = validateSignup(body);
  if (!v.ok) return json({ ok: false, error: v.error }, 400, cors);

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  if (!(await checkRateLimit(ip, env))) {
    return json({ ok: false, error: "Too many sign-ups from this network. Try again later." }, 429, cors);
  }

  if (!env.RESEND_API_KEY || !env.OWNER_EMAIL) {
    return json({ ok: false, error: "Sign-up relay is not configured yet." }, 503, cors);
  }

  const cf = (request as Request & { cf?: { country?: string } }).cf;
  const meta: Meta = {
    timestamp: new Date().toISOString(),
    country: cf?.country ?? "unknown",
    userAgent: (request.headers.get("User-Agent") ?? "unknown").slice(0, 300),
    origin: origin ?? "",
  };
  const from = env.FROM_EMAIL?.trim() || DEFAULT_FROM;
  const mail = buildOwnerEmail(v.value, meta);

  let sent: { ok: boolean; status: number };
  try {
    sent = await sendResend(env, {
      from,
      to: [env.OWNER_EMAIL],
      reply_to: v.value.email,
      subject: mail.subject,
      text: mail.text,
      html: mail.html,
    });
  } catch {
    sent = { ok: false, status: 0 };
  }
  if (!sent.ok) {
    console.error(`Resend owner email failed: status ${sent.status}`);
    return json({ ok: false, error: "Could not record your sign-up right now. Please try again." }, 502, cors);
  }

  // Optional confirmation to the user. Off by default: Resend's sandbox sender
  // (onboarding@resend.dev) only delivers to the account owner's own address.
  if (env.SEND_CONFIRMATION === "true" && !/@resend\.dev>?\s*$/i.test(from)) {
    const c = buildConfirmationEmail(v.value);
    try {
      const r = await sendResend(env, {
        from,
        to: [v.value.email],
        subject: c.subject,
        text: c.text,
        html: c.html,
      });
      if (!r.ok) console.error(`Resend confirmation failed: status ${r.status}`);
    } catch {
      console.error("Resend confirmation failed: network error");
    }
  }

  return json({ ok: true }, 200, cors);
}
