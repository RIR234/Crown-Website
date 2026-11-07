# Crown-Website

## Latest setup: demo wallet and admin dashboard

The frontend and server RPC calls are in `index.html`. The database objects required by them are defined in:

`supabase/migrations/202611070003_demo_wallet_admin.sql`

`supabase/migrations/202611070004_server_authoritative_demo_catalog.sql`

Apply the migrations in numeric order in the Supabase SQL Editor when setting up a fresh project. The second migration seeds all 50 demo tasks and makes the database—not browser-supplied values—the source of task names and prices.

### What it enables

- Server-side demo wallet balance and demo-credit ledger.
- Instant demo order confirmation with balance checks and sequential task enforcement.
- Server-authoritative task titles and prices for all 50 demo tasks; client-supplied prices are ignored.
- Legacy account login using registered email when an account has no User ID yet.
- User-visible demo transaction history.
- Private Admin dashboard with registered users, confirmed demo orders, order value and wallet ledger.
- Admin cancellation/refund of the latest confirmed demo order (demo credits only).

### Important

Demo credits are not money. This setup does not process real deposits, withdrawals, USDT, Binance Pay or cryptocurrency transfers. Do not advertise demo credits as cash or earnings. Real-money wallet features require separately reviewed legal, compliance, payment-provider and security work.

After the SQL migration is applied, sign in using the existing Crown Admin account and open the **Admin** tab. The tab is visible only to accounts whose `profiles.role` is `admin`.
