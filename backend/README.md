# Stripe License Backend (One-Time Purchase)

This backend implements a minimal Stripe lifetime-license flow for TokenBar:

- One-time checkout (`$5`) via Stripe Checkout session
- License key issuance after paid checkout verification
- License verification endpoint for app unlock
- 1-device enforcement per license
- Automatic revocation on refund/dispute webhooks

## Routes

- `GET /healthz`
- `POST /api/checkout/session`
- `POST /api/license/issue-from-session`
- `POST /api/license/verify`
- `POST /api/webhooks/stripe`

## Environment

Copy `backend/.env.example` and set real values.

Required values:

- `STRIPE_SECRET_KEY` (starts with `sk_live_...`)
- `STRIPE_WEBHOOK_SECRET` (starts with `whsec_...`)

Important: the publishable key (`pk_live_...`) is **not** the secret key.

## Run locally

```bash
node backend/license-server.mjs
```

Or from package scripts:

```bash
pnpm license:server
```

## Stripe webhook setup

In Stripe Dashboard:

1. Create a webhook endpoint: `https://your-api-domain.com/api/webhooks/stripe`
2. Subscribe to events:
   - `checkout.session.completed`
   - `charge.refunded`
   - `charge.dispute.created`
3. Copy signing secret into `STRIPE_WEBHOOK_SECRET`

## Success and cancel URLs

Configured defaults:

- `https://tokenbar.site/checkout/success?session_id={CHECKOUT_SESSION_ID}`
- `https://tokenbar.site/checkout/cancel`

The success page should call `POST /api/license/issue-from-session` with:

```json
{
  "session_id": "cs_...",
  "device_id": "..."
}
```

Then show the returned `license_key` to the customer.
