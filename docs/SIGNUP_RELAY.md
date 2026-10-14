# Beta sign-up relay (Cloudflare Worker + Resend)

The web demo on GitHub Pages is a static site, so it cannot keep the Resend API key secret. Instead, the sign-up form posts to a small Cloudflare Worker in `relay/`. The Worker holds the key and emails you each sign-up.

```
browser (GitHub Pages)  --POST /signup-->  Cloudflare Worker (relay/)  --Resend API-->  your inbox
```

What it does:

- Accepts `POST /signup` with JSON `{name, email, plan, trial_months, sport?, notes?, website?}`. `plan` is `monthly`, `annual` or `lifetime`. `trial_months` is a whole number from 0 to 12. `website` is a hidden honeypot field.
- Only accepts requests from allowed origins: `https://bryanzhao08.github.io`, `http://localhost:5173` and `http://localhost:4317` by default. You can change the list with `ALLOWED_ORIGINS` in `relay/wrangler.toml`.
- Emails you a message with the subject `New FormCoach beta sign-up: <plan>`. It includes every field (HTML-escaped), a timestamp, the visitor's country and their browser user agent. Reply-To is set to the person who signed up, so you can reply to them directly.
- Rejects any request that looks like it contains card details (keys like `card`, `cvv`, `pan`, `expiry`, or any 13-19 digit number). These requests get a 400 and are never emailed. Payments only go through the hosted checkout.
- Allows at most 5 sign-ups per IP address per hour.
- Responds with `{"ok":true}` or `{"ok":false,"error":"..."}`.

## Deploy (about 5 minutes, one time)

You need a free Cloudflare account. Every step runs from the `relay/` folder.

1. **Install and log in to Cloudflare.** The login opens a browser window, so you have to run it yourself. Inside Claude Code you can type:

   ```
   ! cd ~/Documents/GitHub/FormCoach/relay && npm install && npx wrangler login
   ```

   In a normal terminal, run `cd ~/Documents/GitHub/FormCoach/relay && npm install && npx wrangler login`.

2. **Store the Resend API key as a secret.** The key is already in `backend/.env`, on the line that starts with `RESEND_API_KEY=`. Open that file, copy everything after the `=` (it starts with `re_`), then run:

   ```
   npx wrangler secret put RESEND_API_KEY
   ```

   Paste the key when it asks. Do not put it in any file in `relay/`, and do not paste it into chat.

3. **Store your own email address as a secret.** Use the address you signed up to Resend with (see "Sender address" below for why):

   ```
   npx wrangler secret put OWNER_EMAIL
   ```

   This is a secret on purpose. Your address never appears in the public repo.

4. **(Optional, recommended) Make the rate limit survive restarts.** If you skip this step, the Worker still rate-limits, but only in memory, as a best effort.

   ```
   npx wrangler kv namespace create SIGNUPS
   ```

   The command prints an `id`. In `relay/wrangler.toml`, uncomment the `[[kv_namespaces]]` block at the bottom and paste that id in.

5. **Deploy:**

   ```
   npx wrangler deploy
   ```

   The command prints a URL like `https://formcoach-signup.<your-account>.workers.dev`. Your sign-up endpoint is that URL plus `/signup`.

6. **Point the website at it.** Set `SIGNUP_URL` in `web/src/config.ts` (Claude is adding this setting) to `https://formcoach-signup.<your-account>.workers.dev/signup`, then rebuild and publish the web demo.

## Test it

Replace the URL with yours. The `Origin` header has to be an allowed origin:

```
curl -i -X POST https://formcoach-signup.<your-account>.workers.dev/signup \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://bryanzhao08.github.io' \
  -d '{"name":"Test User","email":"test@example.com","plan":"annual","trial_months":1,"sport":"Tennis","notes":"curl test"}'
```

You should get `{"ok":true}`, and the email should arrive within a few seconds (check spam the first time). To watch the Worker's logs live, run `npx wrangler tail`.

Common errors:

| Response | Meaning |
| --- | --- |
| 403 `Origin not allowed.` | The `Origin` header is missing or not in `ALLOWED_ORIGINS`. |
| 503 `Sign-up relay is not configured yet.` | `RESEND_API_KEY` or `OWNER_EMAIL` secret is missing (steps 2-3). |
| 502 `Could not record your sign-up...` | Resend rejected the send. Run `npx wrangler tail` to see the status code. A 403 from Resend usually means `OWNER_EMAIL` is not your Resend account's address. |
| 429 | More than 5 sign-ups from that IP address in the current hour. |

## Sender address and confirmation emails

The default sender is `FormCoach Beta <onboarding@resend.dev>`, Resend's sandbox address. It works without any domain setup, but **Resend only delivers it to the email address that owns the Resend account**. That is fine for notifying you, which is why `OWNER_EMAIL` must be that address.

Because of that limit, the Worker does **not** email the person who signed up (`SEND_CONFIRMATION = "false"`). The sandbox sender cannot reach other people. Even if you turn the setting on, the Worker skips the confirmation while the sender is still `@resend.dev`. To send confirmations later:

1. Verify a domain you own in the Resend dashboard (Domains, then Add domain, then add the DNS records it shows).
2. In `relay/wrangler.toml`, set `FROM_EMAIL = "FormCoach <beta@yourdomain.com>"` and `SEND_CONFIRMATION = "true"`.
3. Run `npx wrangler deploy` again.

## Free-tier limits

Checked 2026-10-13. A beta sign-up form will not get close to these.

- **Cloudflare Workers Free:** 100,000 requests per day. The count resets at midnight UTC. Source: https://developers.cloudflare.com/workers/platform/limits/
- **Workers KV Free** (only if you did step 4): 100,000 reads and 1,000 writes per day. Each sign-up uses one write. Source: https://developers.cloudflare.com/kv/platform/limits/
- **Resend Free:** 100 emails per day and 3,000 emails per month. Each sign-up uses one email, or two if confirmations are on. Source: https://resend.com/pricing

## Local development

```
cd relay
cp .dev.vars.example .dev.vars   # then fill in real values; .dev.vars is git-ignored
npm run dev                      # serves on http://localhost:8787/signup
npm test                         # unit tests (vitest), no network needed
npm run typecheck
```
