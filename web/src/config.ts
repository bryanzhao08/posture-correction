// Beta settings for the public web demo. Change these and push to main; the site redeploys itself.

export const BETA = {
  /** SHA-256 of "formcoach-beta:" + password. Change with: npm run set-password -- <new password>
   *  This only keeps casual visitors out: the site is static, so it is not real security. */
  passwordHash: "e5c89ed3dc7bd1c57a537aaf920325b089b9682f2fc0cb2e0385feff509137d6",
  /** Length of the free trial shown to beta testers. */
  trialMonths: 3,
  /** Sign-up relay (relay/, a Cloudflare Worker that emails you via Resend). Empty = sign-ups closed.
   *  After `npx wrangler deploy` in relay/, paste "<workers.dev URL>/signup" here. */
  signupUrl: (import.meta.env.VITE_SIGNUP_URL as string | undefined) || "",
  /** Hosted checkout links (e.g. Stripe Payment Links with a free trial). Card details are entered on the
   *  payment provider's page and never pass through FormCoach. Empty = button hidden. */
  checkout: {
    monthly: "",
    annual: "",
    lifetime: "",
  },
};

export const PLANS = [
  { id: "monthly", name: "Monthly", price: "$4.99", per: "/ month", note: "Cancel any time" },
  { id: "annual", name: "Annual", price: "$39.99", per: "/ year", note: "Save 33% vs monthly", best: true },
  { id: "lifetime", name: "Lifetime", price: "$99.99", per: "once", note: "Pay once, keep it forever" },
] as const;

export type PlanId = (typeof PLANS)[number]["id"];
