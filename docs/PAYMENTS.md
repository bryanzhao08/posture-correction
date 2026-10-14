# FormCoach Founder’s Guide to Payments & Subscriptions

This guide explains how FormCoach handles payments, subscriptions, and free trials across the Web demo and the iOS App Store. It is written for non-technical founders to set up and manage revenue without touching low-level code or risking compliance penalties.

---

## 1. Product Pricing & Stripe Payment Links Setup

FormCoach offers three simple pricing tiers:
* **Monthly Subscription:** $4.99 / month (with a 3-month free trial)
* **Annual Subscription:** $39.99 / year (with a 3-month free trial; saves 33%)
* **Lifetime Access:** $99.99 one-time payment (instant lifetime access)

```
+----------------------------------------------------------------------------------------------------+
|                                    FORMCOACH PRICING ARCHITECTURE                                  |
+----------------------------------------------------------------------------------------------------+
|  1. Monthly Subscription      |  2. Annual Subscription       |  3. Lifetime Access                |
|  $4.99 / month                |  $39.99 / year                |  $99.99 one-time                   |
|  (90-day free trial)          |  (90-day free trial)          |  (Pay once, keep forever)          |
+----------------------------------------------------------------------------------------------------+
|  Stripe Payment Link          |  Stripe Payment Link          |  Stripe Payment Link               |
|  https://buy.stripe.com/...   |  https://buy.stripe.com/...   |  https://buy.stripe.com/...        |
+-------------------------------+-------------------------------+------------------------------------+
|                               Pasted into web/src/config.ts:                                       |
|                               BETA.checkout.monthly / annual / lifetime                            |
+----------------------------------------------------------------------------------------------------+
```

### Free Trial Duration Rules (Stripe Limits)
* **Current FormCoach Setting:** 3 months (set as 90 days in Stripe).
* **Maximum Allowed by Stripe:** Stripe allows a maximum trial length of **730 days (2 full years)** via its [`trial_period_days`](https://docs.stripe.com/payments/checkout/free-trials) parameter ([Stripe Free Trials Documentation](https://docs.stripe.com/payments/checkout/free-trials)). FormCoach’s 90-day trial is well within Stripe’s operational ceiling.

---

### Step-by-Step: Creating the 3 Stripe Payment Links

You can create hosted checkout links directly in the Stripe Dashboard without writing any code ([Stripe Payment Links Guide](https://docs.stripe.com/payment-links)):

#### Step A: Create the Monthly Subscription ($4.99/mo + 90-Day Free Trial)
1. Log in to your [Stripe Dashboard](https://dashboard.stripe.com/).
2. In the top search bar, type **Payment Links** and press Enter (or go to `More > Payment Links`).
3. Click the blue **+ New** button in the top-right corner.
4. Under **Select type**, ensure **Products or subscriptions** is chosen.
5. In the **Product** dropdown, click **+ Add a new product**:
   * **Name:** `FormCoach Beta - Monthly`
   * **Price:** `4.99`
   * **Currency:** `USD`
   * **Billing period:** `Monthly`
   * Click **Add product**.
6. Under the product settings in Payment Links, toggle on **Free trial**.
   * Enter `90` days (representing the 3-month trial).
   * Note: Stripe will securely capture the customer's payment method upfront, but will not charge the card until day 91.
7. Under **Advanced options**:
   * Ensure **Customer emails** is set to required (checked by default).
   * Leave **Save payment details for future use** checked.
8. Click **Create link** in the top right. Copy the link (it looks like `https://buy.stripe.com/test_...` or `https://buy.stripe.com/...`).

#### Step B: Create the Annual Subscription ($39.99/yr + 90-Day Free Trial)
1. Click **+ New** in Payment Links again.
2. Click **+ Add a new product**:
   * **Name:** `FormCoach Beta - Annual`
   * **Price:** `39.99`
   * **Currency:** `USD`
   * **Billing period:** `Yearly`
   * Click **Add product**.
3. Toggle on **Free trial** and enter `90` days.
4. Click **Create link** and copy the resulting `https://buy.stripe.com/...` URL.

#### Step C: Create the Lifetime Access ($99.99 One-Time)
1. Click **+ New** in Payment Links.
2. Click **+ Add a new product**:
   * **Name:** `FormCoach Lifetime Access`
   * **Price:** `99.99`
   * **Currency:** `USD`
   * **Billing period:** Select **One-time** (Note: One-time payments cannot have subscription free trials; access is granted immediately).
   * Click **Add product**.
3. Click **Create link** and copy the resulting `https://buy.stripe.com/...` URL.

---

### Where the Stripe URLs Go in the Codebase

Once you generate your three live Stripe links, paste them into the file [`web/src/config.ts`](../web/src/config.ts) under the `BETA.checkout` object:

```typescript
// Located in: web/src/config.ts
export const BETA = {
  trialMonths: 3,
  
  /** Hosted checkout links (Stripe Payment Links with a free trial). */
  checkout: {
    monthly: "https://buy.stripe.com/your_monthly_link_here",
    annual: "https://buy.stripe.com/your_annual_link_here",
    lifetime: "https://buy.stripe.com/your_lifetime_link_here",
  },
};
```

When those strings are populated, FormCoach’s pricing modal automatically reveals clickable "Start Free Trial" and "Get Lifetime Access" buttons that route users directly to Stripe’s secure checkout page.

---

## 2. Notifications, Customer Receipts & Self-Service Cancellations

### How You (the Owner) Get Notified of Sales and Trials
You do not need an email server or custom webhooks to know when people sign up. Stripe provides automated email alerts ([Stripe Email Settings](https://dashboard.stripe.com/settings/emails)):
1. Navigate to **Stripe Dashboard > Settings (gear icon) > User Settings > Communication & Notifications** (or visit [dashboard.stripe.com/settings/user](https://dashboard.stripe.com/settings/user)).
2. Under **Email notifications**, toggle on:
   * **Successful payments:** Sends you an email the instant an account is charged.
   * **Customer subscription created / trial started:** Alerts you when a new beta tester activates their 90-day trial.

### Automated Customer Receipts
Under legal card-network regulations, customers must receive receipts and trial reminders ([Stripe Customer Emails](https://docs.stripe.com/receipts)):
1. Go to **Stripe Dashboard > Settings > Customer emails** ([dashboard.stripe.com/settings/emails](https://dashboard.stripe.com/settings/emails)).
2. Toggle on **Email customers for successful payments** and **Email customers for refunds**.
3. Toggle on **Upcoming trial expiration reminder**: Stripe automatically emails the customer 3 to 7 days before their 90-day trial ends, reminding them of the upcoming charge and reducing chargebacks.
4. Upload the FormCoach logo and enter your support email (e.g., `support@formcoach.app`).

### Customer Self-Service Portal (Handling Cancellations)
FormCoach does not need to build custom cancellation screens. Stripe provides a free, hosted **Customer Portal** where users can update credit cards, download invoices, or cancel their subscriptions ([Stripe Customer Portal Documentation](https://docs.stripe.com/no-code/customer-portal)):
1. In Stripe, navigate to **Settings > Billing > Customer Portal** ([dashboard.stripe.com/settings/billing/portal](https://dashboard.stripe.com/settings/billing/portal)).
2. Click **Activate link**.
3. Under **Subscription management**, ensure **Cancel subscriptions** is toggled ON ([Stripe Cancellation Settings](https://docs.stripe.com/customer-management/cancellation-page)).
4. Choose when cancellations take effect: Select **At the end of the current billing period** so customers retain access for the days they already earned.
5. Under **Cancellation reasons**, enable survey questions (e.g., *"Too expensive"*, *"Found an alternative"*, *"Quality below expectations"*).
6. Copy your permanent Customer Portal URL and paste it into your welcome emails or user settings menu.

---

## 3. Why FormCoach Must NEVER Collect or Email Card Numbers

> **PCI DSS in three sentences:**
>
> Any business that receives, stores or sends card numbers itself falls under the full Payment Card Industry Data Security Standard ([PCI DSS](https://www.pcisecuritystandards.org/)), with its security controls, assessments and breach liability. Sending card numbers by email is exactly the kind of unprotected transmission the standard forbids, and card networks and processors can fine or drop merchants that do it. Because FormCoach sends people to Stripe-hosted Payment Links, card data goes straight from the customer's browser to Stripe, which keeps FormCoach on the simplest self-assessment (SAQ A).

---

## 4. Apple App Store Rules & Anti-Steering Policies

```
+----------------------------------------------------------------------------------------------------+
|                                  PLATFORM PAYMENT ARCHITECTURE                                     |
+----------------------------------------------------------------------------------------------------+
|                                                                                                    |
|   1. WEB DEMO (Safari, Chrome, Desktop)                2. NATIVE iOS APP (iPhone, iPad)             |
|   -------------------------------------                --------------------------------            |
|   * Platform: Open Web Browser                         * Platform: Apple App Store                 |
|   * Engine: Stripe Hosted Checkout                     * Engine: Apple StoreKit 2 (Native IAP)     |
|   * Payment: Cards, Apple Pay on Web                   * Payment: Apple ID Payment                 |
|   * Fees: 2.9% + 30c per transaction                   * Fees: 15% (Small Business) / 30%          |
|   * Web users log into iOS without repaying            * Can link out to Web in US (Rule 3.1.1(a)) |
|                                                                                                    |
+----------------------------------------------------------------------------------------------------+
```

### Apple App Store Rule 3.1.1: In-App Purchases
* **The Core Rule:** Under [Apple App Review Guideline 3.1.1](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase), any digital features, premium analysis, or subscription access unlocked inside an iOS app downloaded from the App Store **must** offer Apple’s native In-App Purchase mechanism via StoreKit ([Apple In-App Purchase Overview](https://developer.apple.com/in-app-purchase/)).
* You cannot deploy an iOS app that *only* displays a Stripe button or forces users to open a browser to pay.

### The 2024–2025 US Anti-Steering Ruling (Epic v. Apple)
* **What Happened:** Following the *Epic Games v. Apple* federal antitrust litigation, U.S. District Judge Yvonne Gonzalez Rogers issued an anti-steering injunction. In 2024–2025, the court held Apple in civil contempt for attempting to charge an arbitrary 27% tax on external links and imposing restrictive "scare warning" screens ([Oyez Epic v. Apple Case Summary](https://www.oyez.org/cases/2023/23-118)).
* **What Changed:** In the United States storefront (under Guideline 3.1.1(a)), developers can now include outbound links, buttons, and text informing users that alternative purchasing options exist on the web ([Apple StoreKit External Link Entitlement](https://developer.apple.com/support/storekit-external-link-entitlement-us/)).
* **What Remains:** Apple still requires that native In-App Purchase be available inside the app, and the legal framework for external commissions remains subject to appellate review.

### What This Means for FormCoach
1. **Web Demo (`web/`):** Operates on the open web. It uses Stripe Payment Links exclusively. Apple is not involved and receives 0% commission.
2. **Native iOS App (`ios/FormCoach/`):** Must use **Apple StoreKit 2** to offer the identical three products:
   * Monthly Subscription ($4.99 with introductory 3-month free trial).
   * Annual Subscription ($39.99 with introductory 3-month free trial).
   * Lifetime Non-Consumable IAP ($99.99).
3. **Multi-Platform Access (Guideline 3.1.3(b)):** Under Apple's "Multiplatform Services" rule, if a customer subscribes on the Web via Stripe, FormCoach is legally allowed to let that customer log into their account inside the iOS app and unlock their premium features without paying Apple a second time ([Apple App Review Guideline 3.1.3(b)](https://developer.apple.com/app-store/review/guidelines/#multiplatform-services)).

---

## 5. Transaction Fees & Profitability Comparison

| Plan | Price | Stripe Web Fee (2.9% + 30¢) | Stripe Net Proceeds | Apple Fee (15% Small Business) | Apple Net Proceeds | Founder Advantage with Stripe |
|---|---|---|---|---|---|---|
| **Monthly** | $4.99 | $0.44 (8.8%) | **$4.55** | $0.75 (15.0%) | **$4.24** | **+$0.31 / mo** (+7.3%) |
| **Annual** | $39.99 | $1.46 (3.65%) | **$38.53** | $6.00 (15.0%) | **$33.99** | **+$4.54 / yr** (+13.4%) |
| **Lifetime** | $99.99 | $3.20 (3.2%) | **$96.79** | $15.00 (15.0%) | **$84.99** | **+$11.80 once** (+13.9%) |

### Key Takeaways on Fees:
* **Apple Small Business Program:** Qualifies developers making under $1,000,000 per year for a reduced **15% commission** (instead of the standard 30%) ([Apple Small Business Program](https://developer.apple.com/app-store/small-business-program/)). You must enroll manually in App Store Connect.
* **Why Annual Web Signups Win:** On every annual subscriber acquired via the web rather than iOS, FormCoach pockets an extra **$4.54**.
* **Payment Method Support:** Stripe Payment Links automatically display Apple Pay, Google Pay, and credit cards in supported browsers, giving web users the same one-tap checkout convenience as the App Store.

---

## 6. The 10-Step Founder Launch Checklist

```
+----------------------------------------------------------------------------------------------------+
|                                    10-STEP LAUNCH CHECKLIST                                        |
+----------------------------------------------------------------------------------------------------+
| [ ] 1. Open Stripe Dashboard and complete identity/payout verification.                            |
| [ ] 2. Create the Monthly product ($4.99) with a 90-day free trial in Payment Links.               |
| [ ] 3. Create the Annual product ($39.99) with a 90-day free trial in Payment Links.                |
| [ ] 4. Create the Lifetime product ($99.99 one-time) in Payment Links.                             |
| [ ] 5. Copy the 3 URLs and paste them into web/src/config.ts under BETA.checkout.                  |
| [ ] 6. Turn on "Successful payments" & "Trial started" alerts in Stripe user settings.            |
| [ ] 7. Enable customer receipts and 7-day trial expiration warnings in Stripe email settings.      |
| [ ] 8. Activate the Stripe Customer Portal and turn on self-service subscription cancellation.     |
| [ ] 9. Enroll in the Apple Small Business Program (15% rate) in App Store Connect.                |
| [ ] 10. Configure matching Monthly, Annual, and Lifetime products in Apple StoreKit 2.            |
+----------------------------------------------------------------------------------------------------+
```

1. **Activate Stripe Account:** Log in to [Stripe](https://dashboard.stripe.com/) and complete business identity verification and bank payout details.
2. **Build Monthly Payment Link:** Create the $4.99/mo recurring product with a 90-day free trial toggle enabled.
3. **Build Annual Payment Link:** Create the $39.99/yr recurring product with a 90-day free trial toggle enabled.
4. **Build Lifetime Payment Link:** Create the $99.99 one-time product (no trial).
5. **Update Web Configuration:** Copy the three `https://buy.stripe.com/...` links and paste them into [`web/src/config.ts`](../web/src/config.ts).
6. **Set Owner Email Alerts:** Toggle on owner email notifications in [Stripe User Settings](https://dashboard.stripe.com/settings/user) for all new sales and trials.
7. **Configure Customer Emails:** Enable automated receipts and upcoming trial-end warning emails in [Stripe Customer Email Settings](https://dashboard.stripe.com/settings/emails).
8. **Enable Customer Portal:** Activate the self-service [Stripe Customer Portal](https://dashboard.stripe.com/settings/billing/portal) with cancellation surveys enabled.
9. **Apply for Apple Small Business Program:** Apply in [App Store Connect](https://developer.apple.com/app-store/small-business-program/) to lock in the 15% rate (saving 50% vs. the 30% standard rate).
10. **Configure StoreKit 2 in iOS:** Match the three product IDs (`formcoach.monthly`, `formcoach.annual`, `formcoach.lifetime`) in App Store Connect with identical prices and introductory trial offers.
