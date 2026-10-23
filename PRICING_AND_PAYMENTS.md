# InSaNe Straps — Pro pricing and payment flow

## Plans (INR)

| Plan | Price |
|---|---:|
| Free | ₹0 |
| Pro — 1 week | ₹39 |
| Pro — 1 month | ₹79 |
| Pro — 1 year | ₹390 |
| Pro — Lifetime | ₹699 |

## Payment methods

- UPI ID supplied by the owner: `akanksha1105@fam`
- Litecoin (LTC) address supplied by the owner: `LaLmC3Hwtuf72fd59S4deUoBUpdxNS14dK`

## Intended purchase flow

1. User chooses a plan and payment method.
2. Show the exact INR plan price and the UPI ID or LTC address.
3. For LTC, fetch a current LTC/INR and LTC/USD quote from a reputable price source at checkout. Show the quote timestamp, amount in LTC, approximate USD equivalent, and a note that the exchange rate/network fee can change before confirmation. Never hard-code a live exchange rate.
4. User submits a transaction reference or transaction ID. Do not treat screenshots or a client-side button as proof of payment.
5. Keep the purchase as **Pending** until an owner/admin verifies the UPI transaction or the LTC transaction on-chain, including amount and confirmations.
6. After confirmation, grant the selected entitlement on the server and show it in the user's account.
7. Owner dashboard can grant/revoke Pro for a selected account, with an audit log and reason.
8. Owner can generate a single-use Pro key with a plan/duration and expiry policy. The redemption endpoint must validate the key on the server, atomically mark it redeemed, and record the account that redeemed it.

## Security requirements before launch

- Never put owner credentials, payment API secrets, signing keys, or admin authority in Flutter/client code or public repository files.
- Enforce plan duration, lifetime entitlement, 2-device limit, trial expiry, key redemption and revocation on the server.
- Authenticate and authorize every owner-dashboard action on the backend; do not grant admin access merely because a username equals `insane`.
- Rate-limit key redemption and login; store only hashed redeemable keys.
- Use server-side transaction verification where provider APIs are available. Manual review is the fallback; never automatically unlock Pro from a user-provided screenshot alone.
- Publish clear refund/support terms before accepting payments.

**Status:** This file records the requested pricing and proposed flow. It does not mean checkout, live LTC conversion, payment verification, account entitlements, or the owner dashboard have been implemented.
