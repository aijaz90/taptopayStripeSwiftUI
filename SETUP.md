# MyTon — Tap to Pay setup

## Backend
The app talks to the local **eventFun** Node.js server.

- Base URL is set in `MyTon/Networking/APIConfig.swift`
  - Physical iPhone (same Wi-Fi): `http://192.168.100.191:3000`
  - iOS Simulator: `http://localhost:3000`
- Start the server: `cd ~/Desktop/eventFun && npm start`

Endpoints used:
- `POST /connection_token` — Stripe Terminal connection token
- `POST /create_payment_intent` — `{ "amount": 2500, "currency": "usd" }` (amount in cents)
- `POST /capture_payment` — `{ "payment_intent_id": "pi_…", "simulate_failure": false }`
- `POST /receipt` — `{ "payment_intent_id": "pi_…" }`

## Open the workspace
After `pod install`, always open **`MyTon.xcworkspace`** (not the `.xcodeproj`).

## Info.plist — allow local HTTP (App Transport Security)
The dev server is plain HTTP, which iOS blocks by default. In the target's
**Info** tab add:

```
App Transport Security Settings (Dictionary)
  Allow Arbitrary Loads = YES
```

(For production use HTTPS and remove this.)

## Tap to Pay on iPhone requirements
Real contactless collection via `StripeTerminal` requires:

1. A physical **iPhone XS or newer**, iOS 16.7+ (Tap to Pay does **not** run in the Simulator).
2. The **Tap to Pay entitlement** from Apple:
   `com.apple.developer.proximity-reader.payment.acceptance`
   Request it for your App ID, then add it to the target's `.entitlements`.
3. A **real Stripe secret key** (`sk_…`) on the backend. The current
   `/connection_token` returns a placeholder key, which is enough to wire up
   the UI but Stripe's SDK needs a token minted server-side with your secret
   key via `POST https://api.stripe.com/v1/terminal/connection_tokens`.

To go live, in `MyTonApp.swift` set the token provider on launch:

```swift
import StripeTerminal
Terminal.setTokenProvider(StripeConnectionTokenProvider())
```

then discover + connect a Tap to Pay reader and call
`collectPaymentMethod` / `confirmPaymentIntent`.

## Real Stripe Terminal flow (waits for a real card tap)

The app now has a real `TerminalManager` that does:
`discover → connect → collectPaymentMethod (waits for the tap) → confirmPaymentIntent`
and builds the receipt from the **actual card that was tapped**.

Three ways to run it, chosen with the toggles on the screen:

| Toggles | What happens |
|---|---|
| Real Terminal ON + Simulated reader ON | **Best for testing now.** Full real SDK flow with Stripe's *simulated* reader — no entitlement, no physical card, works even on Simulator. |
| Real Terminal ON + Simulated reader OFF | **Real Tap to Pay.** Needs the entitlement + physical iPhone; waits for a real card tap. |
| Real Terminal OFF | Old mock button flow (fake receipt); the "Simulate declined card" toggle tests the error UI. |

### To enable the REAL backend (required for anything beyond the mock)
1. Put your Stripe **secret** key in `eventFun/server.js` → `STRIPE_SECRET_KEY`
   (use `sk_test_…` for testing). Or run: `STRIPE_SECRET_KEY=sk_test_xxx npm start`.
   The server logs `Stripe REAL mode enabled` when it's set correctly.
2. Restart the server. `/connection_token` now returns a real token and
   `/create_payment_intent` creates a real `card_present` PaymentIntent.

### To enable REAL physical Tap to Pay (simulated reader OFF)
1. Add Apple's entitlement `com.apple.developer.proximity-reader.payment.acceptance`
   to your App ID (Apple Developer portal) and to a `MyTon.entitlements` file, then
   set the target's *Code Signing Entitlements* to it. (Signing fails until Apple
   grants it, so leave this off until then.)
2. Add `NSLocationWhenInUseUsageDescription` to Info.plist (Terminal needs location).
3. Run on a physical **iPhone XS+ / iOS 16.7+**, signed into iCloud.

> ⚠️ **Country availability:** Tap to Pay on iPhone via Stripe is only supported for
> Stripe accounts in specific countries. Confirm your Stripe account's country is on
> Stripe's supported list — if it isn't, the *real* reader won't activate (the
> **simulated reader** still works everywhere for testing).
