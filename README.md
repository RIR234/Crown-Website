# Crown Website

## Current deployment

- Live site: https://crown-website-livid.vercel.app
- Frontend: `index.html`
- Backend: Supabase project (Auth, PostgreSQL, Edge Functions)
- Deployment: Vercel automatically deploys commits from `main`.

## Features currently implemented

- Email signup with unique lowercase User ID; login accepts User ID or registered email.
- Password reset, profile details, User ID and email updates.
- Dashboard tabs: Home, Work, League and Settings.
- Server-authoritative demo wallet and transaction ledger.
- Instant demo order confirmation when the account has sufficient demo balance; insufficient balance is rejected.
- Server-side task catalogue with 50 fixed demo tasks; the server ignores client-supplied task names and prices.
- Sequential demo task progression.
- User transaction history and browser/email notification options.
- Admin-only dashboard with user list, demo balances, confirmed orders and ledger.
- Admin can add or deduct demo credits with a note; server checks admin permissions and prevents negative balances.
- Admin can cancel a confirmed demo order and refund its demo credits.
- Dashboard route is kept in the URL hash so a refresh returns to the selected tab.

## Database migrations

The `supabase/migrations` directory contains the SQL migrations for the demo wallet, authoritative catalogue, ledger permissions, unique User IDs, retirement of legacy task approvals, admin balance adjustments and supporting indexes.

For a fresh Supabase project, apply the migration files in timestamp order. The current production database already has these migrations applied.

## Important payment limitation

Crown is currently a **demo platform**, not a live payment service. Demo credits have no cash value. Real BDT deposits/withdrawals, USDT transfers, Binance integration and merchant settlements are not active. Do not send money or cryptocurrency to anyone claiming to fund a Crown account.

Before enabling real-money services, obtain the required Bangladesh legal/compliance review and integrate an authorised payment provider with server-side reconciliation, fraud controls, KYC/AML where required, and audited transaction handling.

## Remaining production prerequisites

- Enable Supabase leaked-password protection in Authentication settings (available on Supabase Pro and above).
- Complete real browser end-to-end tests for signup, email confirmation, login, wallet, orders, admin adjustments and refunds.
- Configure and test a legally approved payment provider before enabling real deposits or withdrawals.

The public website and demo backend are deployed; the items above are deliberately not represented as completed.
