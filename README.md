# Crown-Website

## Latest setup: demo wallet and admin dashboard

The frontend and server RPC calls are in `index.html`. The database objects required by them are defined in:

`supabase/migrations/202611070003_demo_wallet_admin.sql`

Apply that SQL migration once in the Supabase SQL Editor before testing the new wallet or Admin dashboard.

### What it enables

- Server-side demo wallet balance and demo-credit ledger.
- Instant demo order confirmation with balance checks and sequential task enforcement.
- User-visible demo transaction history.
- Private Admin dashboard with registered users, confirmed demo orders, order value and wallet ledger.
- Admin cancellation/refund of the latest confirmed demo order (demo credits only).

### Important

Demo credits are not money. This setup does not process real deposits, withdrawals, USDT, Binance Pay or cryptocurrency transfers. Do not advertise demo credits as cash or earnings. Real-money wallet features require separately reviewed legal, compliance, payment-provider and security work.

After the SQL migration is applied, sign in using the existing Crown Admin account and open the **Admin** tab. The tab is visible only to accounts whose `profiles.role` is `admin`.
