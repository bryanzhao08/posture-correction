import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  CARD_ERROR,
  RESEND_URL,
  _resetMemoryRateLimit,
  checkRateLimit,
  containsCardData,
  escapeHtml,
  handleRequest,
  isAllowedOrigin,
  validateSignup,
  type Env,
  type KVLike,
} from "../src/relay";

const ORIGIN = "https://bryanzhao08.github.io";
const ENV: Env = { RESEND_API_KEY: "re_test_key", OWNER_EMAIL: "owner@example.test" };
const GOOD = {
  name: "Ada Lovelace",
  email: "ada@example.com",
  plan: "annual",
  trial_months: 3,
  sport: "Squash",
  notes: "Excited <b>to</b> try & see",
  website: "",
};

let ipCounter = 0;
function req(body: unknown, opts: { origin?: string | null; method?: string; ip?: string } = {}) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "User-Agent": "vitest-agent",
    "CF-Connecting-IP": opts.ip ?? `10.0.0.${++ipCounter}`,
  };
  const origin = opts.origin === undefined ? ORIGIN : opts.origin;
  if (origin) headers.Origin = origin;
  const method = opts.method ?? "POST";
  return new Request("https://relay.test/signup", {
    method,
    headers,
    body: method === "POST" ? (typeof body === "string" ? body : JSON.stringify(body)) : undefined,
  });
}

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  _resetMemoryRateLimit();
  fetchMock = vi.fn(async () => new Response(JSON.stringify({ id: "email_1" }), { status: 200 }));
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

describe("validateSignup", () => {
  it("accepts a good payload and trims", () => {
    const r = validateSignup({ ...GOOD, name: "  Ada  " });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.name).toBe("Ada");
  });
  it("accepts optional fields missing", () => {
    const { sport, notes, ...rest } = GOOD;
    expect(validateSignup(rest).ok).toBe(true);
  });
  it.each([
    [{ ...GOOD, name: "" }],
    [{ ...GOOD, name: "x".repeat(81) }],
    [{ ...GOOD, name: 42 }],
    [{ ...GOOD, name: "Bad\r\nBcc: x@y.z" }],
    [{ ...GOOD, email: "not-an-email" }],
    [{ ...GOOD, email: "a@b" }],
    [{ ...GOOD, email: `${"a".repeat(110)}@example.com` }],
    [{ ...GOOD, plan: "weekly" }],
    [{ ...GOOD, trial_months: "3" }],
    [{ ...GOOD, trial_months: 1.5 }],
    [{ ...GOOD, trial_months: -1 }],
    [{ ...GOOD, notes: "n".repeat(501) }],
    [{ ...GOOD, notes: 5 }],
    [{ ...GOOD, sport: ["a"] }],
    [null],
    [[GOOD]],
  ])("rejects invalid input %#", (body) => {
    expect(validateSignup(body).ok).toBe(false);
  });
  it("allows notes of exactly 500 and name of exactly 80", () => {
    expect(validateSignup({ ...GOOD, notes: "n".repeat(500), name: "x".repeat(80) }).ok).toBe(true);
  });
});

describe("containsCardData", () => {
  it.each([
    { card: "x" },
    { cc: "1" },
    { CVV: "123" },
    { cvc: "123" },
    { pan: "x" },
    { expiry: "12/30" },
    { card_number: "x" },
    { payment: { cardNumber: "x" } },
    { notes: "my card is 4242424242424242" },
    { notes: "4242 4242 4242 4242" },
    { notes: "4242-4242-4242-4242" },
    { name: "x", extra: [1, "378282246310005"] },
    { n: 4242424242424242 },
  ])("detects %j", (body) => {
    expect(containsCardData(body)).toBe(true);
  });
  it("ignores normal sign-ups and short numbers", () => {
    expect(containsCardData(GOOD)).toBe(false);
    expect(containsCardData({ notes: "call me at 555-123-4567, I train 3x/week since 2019" })).toBe(false);
  });
});

describe("origin check", () => {
  it("uses defaults", () => {
    expect(isAllowedOrigin(ORIGIN, {})).toBe(true);
    expect(isAllowedOrigin("http://localhost:5173", {})).toBe(true);
    expect(isAllowedOrigin("http://localhost:4317", {})).toBe(true);
    expect(isAllowedOrigin("https://evil.example", {})).toBe(false);
    expect(isAllowedOrigin(null, {})).toBe(false);
  });
  it("respects ALLOWED_ORIGINS", () => {
    const env = { ALLOWED_ORIGINS: " https://a.example , https://b.example/ " };
    expect(isAllowedOrigin("https://b.example", env)).toBe(true);
    expect(isAllowedOrigin(ORIGIN, env)).toBe(false);
  });
  it("rejects POST from a foreign origin with 403 and no email", async () => {
    const res = await handleRequest(req(GOOD, { origin: "https://evil.example" }), ENV);
    expect(res.status).toBe(403);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
  it("rejects POST with no Origin", async () => {
    const res = await handleRequest(req(GOOD, { origin: null }), ENV);
    expect(res.status).toBe(403);
  });
  it("answers CORS preflight for allowed origin", async () => {
    const res = await handleRequest(req(null, { method: "OPTIONS" }), ENV);
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(ORIGIN);
    expect(res.headers.get("Access-Control-Allow-Methods")).toContain("POST");
    expect(res.headers.get("Access-Control-Allow-Headers")).toContain("Content-Type");
  });
  it("refuses preflight for other origin", async () => {
    const res = await handleRequest(req(null, { method: "OPTIONS", origin: "https://evil.example" }), ENV);
    expect(res.status).toBe(403);
  });
});

describe("handleRequest", () => {
  it("sends the owner email via Resend with the right payload", async () => {
    const res = await handleRequest(req(GOOD), ENV);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(ORIGIN);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(RESEND_URL);
    expect(init.method).toBe("POST");
    const headers = init.headers as Record<string, string>;
    expect(headers.Authorization).toBe("Bearer re_test_key");
    expect(headers["Content-Type"]).toBe("application/json");
    const payload = JSON.parse(init.body as string);
    expect(payload.from).toBe("FormCoach Beta <onboarding@resend.dev>");
    expect(payload.to).toEqual(["owner@example.test"]);
    expect(payload.reply_to).toBe("ada@example.com");
    expect(payload.subject).toBe("New FormCoach beta sign-up: annual");
    for (const s of ["Ada Lovelace", "ada@example.com", "annual", "Squash", "vitest-agent"]) {
      expect(payload.text).toContain(s);
      expect(payload.html).toContain(s);
    }
    expect(payload.text).toContain("Free trial (months): 3");
    expect(payload.text).toMatch(/Received: \d{4}-\d\d-\d\dT/);
    expect(payload.text).toContain("Country: unknown");
    // HTML escaping
    expect(payload.html).toContain("Excited &lt;b&gt;to&lt;/b&gt; try &amp; see");
    expect(payload.html).not.toContain("<b>to</b>");
  });

  it("uses FROM_EMAIL when set", async () => {
    await handleRequest(req(GOOD), { ...ENV, FROM_EMAIL: "Beta <beta@formcoach.app>" });
    const payload = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(payload.from).toBe("Beta <beta@formcoach.app>");
  });

  it("silently accepts honeypot submissions without emailing", async () => {
    const res = await handleRequest(req({ ...GOOD, website: "http://spam.example" }), ENV);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects card data with 400 and the exact message", async () => {
    for (const body of [{ ...GOOD, cvv: "123" }, { ...GOOD, notes: "4111 1111 1111 1111" }]) {
      const res = await handleRequest(req(body), ENV);
      expect(res.status).toBe(400);
      expect(await res.json()).toEqual({ ok: false, error: CARD_ERROR });
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects card data even when honeypot is filled", async () => {
    const res = await handleRequest(req({ ...GOOD, website: "x", card: "4242" }), ENV);
    expect(res.status).toBe(400);
  });

  it("returns 400 on validation errors and bad JSON", async () => {
    let res = await handleRequest(req({ ...GOOD, plan: "free" }), ENV);
    expect(res.status).toBe(400);
    const j = (await res.json()) as { ok: boolean; error: string };
    expect(j.ok).toBe(false);
    expect(j.error).toMatch(/plan/);
    res = await handleRequest(req("{not json"), ENV);
    expect(res.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("returns 404 for other paths and 405 for GET", async () => {
    const r404 = await handleRequest(new Request("https://relay.test/", { headers: { Origin: ORIGIN } }), ENV);
    expect(r404.status).toBe(404);
    const r405 = await handleRequest(req(null, { method: "GET" }), ENV);
    expect(r405.status).toBe(405);
  });

  it("returns 503 when secrets are missing", async () => {
    const res = await handleRequest(req(GOOD), {});
    expect(res.status).toBe(503);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("returns 502 when Resend fails", async () => {
    fetchMock.mockImplementationOnce(async () => new Response("{}", { status: 422 }));
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await handleRequest(req(GOOD), ENV);
    expect(res.status).toBe(502);
    spy.mockRestore();
  });

  it("does not send a confirmation by default", async () => {
    await handleRequest(req(GOOD), ENV);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("does not send a confirmation from the sandbox sender even if enabled", async () => {
    await handleRequest(req(GOOD), { ...ENV, SEND_CONFIRMATION: "true" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("sends a confirmation when enabled with a verified sender", async () => {
    await handleRequest(req(GOOD), {
      ...ENV,
      SEND_CONFIRMATION: "true",
      FROM_EMAIL: "FormCoach <beta@formcoach.app>",
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const payload = JSON.parse((fetchMock.mock.calls[1][1] as RequestInit).body as string);
    expect(payload.to).toEqual(["ada@example.com"]);
  });

  it("rate limits to 5 per IP per hour (in-memory)", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 7; i++) {
      statuses.push((await handleRequest(req(GOOD, { ip: "1.2.3.4" }), ENV)).status);
    }
    expect(statuses).toEqual([200, 200, 200, 200, 200, 429, 429]);
    expect((await handleRequest(req(GOOD, { ip: "5.6.7.8" }), ENV)).status).toBe(200);
  });
});

describe("rate limit with KV", () => {
  it("uses the SIGNUPS binding", async () => {
    const store = new Map<string, string>();
    const kv: KVLike = {
      get: async (k) => store.get(k) ?? null,
      put: async (k, v) => void store.set(k, v),
    };
    const env: Env = { SIGNUPS: kv };
    const now = Date.UTC(2026, 0, 1, 12, 30);
    for (let i = 0; i < 5; i++) expect(await checkRateLimit("9.9.9.9", env, now)).toBe(true);
    expect(await checkRateLimit("9.9.9.9", env, now)).toBe(false);
    expect(store.size).toBe(1);
    // Next hour window resets.
    expect(await checkRateLimit("9.9.9.9", env, now + 3600_000)).toBe(true);
  });
});

describe("escapeHtml", () => {
  it("escapes all special chars", () => {
    expect(escapeHtml(`<a href="x">'&'</a>`)).toBe("&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;");
  });
});
