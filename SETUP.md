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

## What works right now (without the entitlement)
The full UI flow runs today against the mock backend:
enter amount → **Tap to Pay** → create intent → capture → **receipt screen**.
Flip the **"Simulate a declined card"** toggle to exercise the error UI.
