// Beta access: a password gate, the free-trial clock, plans, and the sign-up form.
// The password check runs in the browser, so it only keeps casual visitors out.
import { BETA, PLANS, type PlanId } from "../config.ts";
import { pref, setPref } from "./store.ts";

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const DAY = 86_400_000;

async function sha256(text: string): Promise<string> {
  if (!crypto?.subtle) return "";
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function isUnlocked(): boolean {
  return !BETA.passwordHash || pref<string>("betaKey", "") === BETA.passwordHash;
}

/** Shows the password screen until the right password is entered, then calls onPass. */
export function gate(app: HTMLElement, onPass: () => void) {
  if (isUnlocked()) return onPass();
  app.innerHTML = `
  <main class="page gate">
    <header class="brand"><div class="logo">FC</div>
      <div><h1>FormCoach</h1><p class="muted">Private beta</p></div></header>
    <section class="card">
      <h3>Enter the beta password</h3>
      <p class="muted">FormCoach is in a private test. Ask the person who sent you this link for the password.</p>
      <form id="gate-form" class="stack">
        <input id="gate-pw" type="password" autocomplete="current-password" placeholder="Password" required aria-label="Beta password">
        <button class="btn primary" type="submit">Unlock</button>
        <p class="bad small" id="gate-err" hidden>That password isn't right.</p>
      </form>
    </section>
    <p class="muted small">Free for ${BETA.trialMonths} months during the beta. Camera video never leaves your device.</p>
  </main>`;
  const form = app.querySelector<HTMLFormElement>("#gate-form")!;
  form.onsubmit = async (e) => {
    e.preventDefault();
    const pw = app.querySelector<HTMLInputElement>("#gate-pw")!.value;
    if ((await sha256("formcoach-beta:" + pw)) === BETA.passwordHash) {
      setPref("betaKey", BETA.passwordHash);
      startTrial();
      onPass();
    } else {
      app.querySelector<HTMLElement>("#gate-err")!.hidden = false;
    }
  };
  app.querySelector<HTMLInputElement>("#gate-pw")!.focus();
}

export function startTrial() {
  if (!pref<number | null>("trialStart", null)) setPref("trialStart", Date.now());
}

export interface Trial { daysLeft: number; endsOn: Date; expired: boolean }

export function trial(): Trial {
  startTrial();
  const start = pref<number>("trialStart", Date.now());
  const end = new Date(start);
  end.setMonth(end.getMonth() + BETA.trialMonths);
  const daysLeft = Math.max(0, Math.round((end.getTime() - Date.now()) / DAY));
  return { daysLeft, endsOn: end, expired: daysLeft === 0 };
}

/** One line for the home screen. */
export function trialBanner(): string {
  const t = trial();
  if (pref<boolean>("signedUp", false)) {
    return `<button class="notice trial ok" id="plans">You're on the beta list (${esc(planName(pref<string>("plan", "annual")))} plan). ${t.expired ? "Your free trial has ended." : `${t.daysLeft} free days left.`} →</button>`;
  }
  return t.expired
    ? `<button class="notice trial bad" id="plans"><strong>Your free trial has ended.</strong> Pick a plan to keep going →</button>`
    : `<button class="notice trial" id="plans"><strong>Free beta: ${t.daysLeft} days left</strong> (until ${t.endsOn.toLocaleDateString()}). See plans →</button>`;
}

const planName = (id: string) => PLANS.find((p) => p.id === id)?.name ?? id;

/** Plans, what the trial means, and the sign-up form (sent to the owner through the relay). */
export function pricing(app: HTMLElement, back: () => void) {
  const t = trial();
  const chosen = pref<PlanId>("plan", "annual");
  app.innerHTML = `
  <main class="page">
    <button class="btn link" id="back">← Back</button>
    <h1>Plans</h1>
    <p>${t.expired ? "Your free trial has ended." : `You're on the free beta: <strong>${t.daysLeft} days left</strong>.`}
      Everything is unlocked while you test. When the trial ends, keep going with one of these:</p>
    <div class="grid plans">
      ${PLANS.map((p) => `<label class="card plan ${p.id === chosen ? "on" : ""}">
          <input type="radio" name="plan" value="${p.id}" ${p.id === chosen ? "checked" : ""}>
          ${"best" in p ? `<span class="badge">Best value</span>` : ""}
          <span class="name">${p.name}</span>
          <span class="price">${p.price} <span class="muted small">${p.per}</span></span>
          <span class="muted small">${p.note}</span>
        </label>`).join("")}
    </div>
    <section class="card">
      <h3>Join the beta list</h3>
      <p class="muted small">Tell us which plan you'd pick. We'll email you before your trial ends; nothing is charged now.</p>
      ${BETA.signupUrl ? `
      <form id="signup" class="stack" novalidate>
        <input name="name" autocomplete="name" placeholder="Your name" maxlength="80" required aria-label="Name">
        <input name="email" type="email" autocomplete="email" placeholder="Email" maxlength="120" required aria-label="Email">
        <select name="sport" aria-label="Main sport"><option value="">Main sport (optional)</option>
          <option>Tennis</option><option>Golf</option><option>Pickleball</option><option>Basketball</option></select>
        <textarea name="notes" maxlength="500" rows="3" placeholder="Anything we should know? (optional)"></textarea>
        <input name="website" tabindex="-1" autocomplete="off" class="hp" aria-hidden="true">
        <button class="btn primary" type="submit">Join the beta</button>
        <p class="small" id="signup-msg" role="status"></p>
      </form>` : `<p class="muted">Sign-ups open soon.</p>`}
    </section>
    ${Object.values(BETA.checkout).some(Boolean) ? `
    <section class="card">
      <h3>Ready to subscribe?</h3>
      <div class="row gap">${PLANS.filter((p) => BETA.checkout[p.id]).map((p) =>
        `<a class="btn ${p.id === chosen ? "primary" : "ghost"}" href="${esc(BETA.checkout[p.id])}" target="_blank" rel="noopener">${p.name} · ${p.price}</a>`).join("")}</div>
      <p class="muted small">Checkout is hosted by our payment provider. FormCoach never sees or stores your card number.</p>
    </section>` : ""}
  </main>`;
  app.querySelector<HTMLButtonElement>("#back")!.onclick = back;
  app.querySelectorAll<HTMLInputElement>("input[name=plan]").forEach((r) => r.onchange = () => {
    setPref("plan", r.value);
    app.querySelectorAll(".plan").forEach((el) => el.classList.toggle("on", el.contains(r)));
  });
  const form = app.querySelector<HTMLFormElement>("#signup");
  if (form) form.onsubmit = (e) => { e.preventDefault(); void submit(form); };
}

async function submit(form: HTMLFormElement) {
  const msg = form.querySelector<HTMLElement>("#signup-msg")!;
  const data = new FormData(form);
  const name = String(data.get("name") ?? "").trim();
  const email = String(data.get("email") ?? "").trim();
  if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    msg.className = "small bad";
    msg.textContent = "Please enter your name and a valid email.";
    return;
  }
  const btn = form.querySelector<HTMLButtonElement>("button[type=submit]")!;
  btn.disabled = true;
  msg.className = "small muted";
  msg.textContent = "Sending…";
  try {
    const res = await fetch(BETA.signupUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name, email, plan: pref<PlanId>("plan", "annual"), trial_months: BETA.trialMonths,
        sport: String(data.get("sport") ?? ""), notes: String(data.get("notes") ?? ""),
        website: String(data.get("website") ?? ""),
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || !body.ok) throw new Error(body.error || `HTTP ${res.status}`);
    setPref("signedUp", true);
    msg.className = "small good";
    msg.textContent = "You're on the list. Thanks for testing FormCoach!";
    form.reset();
  } catch (err) {
    msg.className = "small bad";
    msg.textContent = `Couldn't send that (${(err as Error).message}). Please try again in a minute.`;
  } finally {
    btn.disabled = false;
  }
}
