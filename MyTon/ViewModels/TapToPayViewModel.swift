//
//  TapToPayViewModel.swift
//  MyTon
//
//  Drives the Tap to Pay screen: connection token -> payment intent ->
//  capture -> receipt, with error handling.
//

import Foundation
import Combine

@MainActor
final class TapToPayViewModel: ObservableObject {

    // MARK: - Inputs
    @Published var amountText: String = "25.00"
    @Published var currency: String = "usd"
    /// Use the real Stripe Terminal SDK flow (waits for a real card tap).
    /// Turn off to use the mock button flow.
    @Published var useRealTerminal: Bool = true
    /// Use Stripe's simulated reader so you can test the full real flow
    /// without the entitlement / a physical card. Turn off for a real tap.
    @Published var useSimulatedReader: Bool = true
    /// (Mock flow only) exercise the failure/error UI.
    @Published var simulateFailure: Bool = false

    // MARK: - Outputs
    @Published private(set) var statusMessage: String = "Ready to take a payment."
    @Published private(set) var isProcessing: Bool = false
    @Published var receipt: ReceiptData?
    @Published var errorMessage: String?
    @Published var showReceipt: Bool = false

    private let api = APIClient.shared

    /// Amount entered by the user converted to the smallest unit (cents).
    private var amountInCents: Int? {
        guard let value = Double(amountText.trimmingCharacters(in: .whitespaces)), value > 0 else {
            return nil
        }
        return Int((value * 100).rounded())
    }

    // MARK: - Flow

    /// Full Tap to Pay flow triggered by the button.
    func startPayment() async {
        print("💳 [TapToPay] startPayment tapped. amountText=\(amountText) currency=\(currency) simulateFailure=\(simulateFailure)")
        errorMessage = nil
        receipt = nil

        guard let amount = amountInCents else {
            print("⚠️ [TapToPay] Invalid amount entered: \(amountText)")
            errorMessage = "Please enter a valid amount greater than 0."
            return
        }
        print("💳 [TapToPay] Amount in cents = \(amount)")

        isProcessing = true
        defer {
            isProcessing = false
            print("💳 [TapToPay] Flow finished. isProcessing=false")
        }

        do {
            let receipt: ReceiptData
            if useRealTerminal {
                receipt = try await runRealTerminalFlow(amount: amount)
            } else {
                receipt = try await runMockFlow(amount: amount)
            }

            // Show the receipt.
            self.receipt = receipt
            self.showReceipt = true
            statusMessage = "Payment successful."
            print("🧾 [TapToPay] showing receipt screen.")
        } catch let error as APIError {
            // Declined card / validation / not-found -> show server message.
            print("❌ [TapToPay] APIError: \(error.message)")
            errorMessage = error.message
            statusMessage = "Payment failed."
        } catch {
            print("❌ [TapToPay] Unexpected error: \(error.localizedDescription)")
            errorMessage = "Something went wrong: \(error.localizedDescription)"
            statusMessage = "Payment failed."
        }
    }

    // MARK: - Real Stripe Terminal flow (waits for a real card tap)

    private func runRealTerminalFlow(amount: Int) async throws -> ReceiptData {
        // 1. Location id used to connect the Tap to Pay reader.
        statusMessage = "Fetching location…"
        print("➡️ [TapToPay] REAL: fetching terminal location…")
        let location = try await api.fetchLocation()

        // 2. Create a card-present PaymentIntent on the backend.
        statusMessage = "Creating payment…"
        print("➡️ [TapToPay] REAL: creating card_present payment intent amount=\(amount)…")
        let intent = try await api.createPaymentIntent(amount: amount, currency: currency)
        print("✅ [TapToPay] REAL: intent=\(intent.id) clientSecret=\(intent.clientSecret.prefix(18))…")

        // 3. Discover + connect reader, then WAIT for the physical tap and confirm.
        print("➡️ [TapToPay] REAL: handing off to StripeTerminal (simulated=\(useSimulatedReader))…")
        let receipt = try await TerminalManager.shared.runPayment(
            clientSecret: intent.clientSecret,
            simulated: useSimulatedReader,
            locationId: location.locationId
        )
        print("✅ [TapToPay] REAL: paid. card=\(receipt.cardBrand) ••\(receipt.cardLast4) amount=\(receipt.amountDisplay)")
        return receipt
    }

    // MARK: - Mock flow (button only, no real card)

    private func runMockFlow(amount: Int) async throws -> ReceiptData {
        statusMessage = "Connecting…"
        _ = try await api.fetchConnectionToken()

        statusMessage = "Creating payment…"
        let intent = try await api.createPaymentIntent(amount: amount, currency: currency)

        statusMessage = "Capturing (mock — no real tap)…"
        print("➡️ [TapToPay] MOCK: capturing WITHOUT real card tap. intent=\(intent.id)")
        return try await api.capturePayment(
            paymentIntentId: intent.id,
            simulateFailure: simulateFailure
        )
    }

    func reset() {
        print("🔄 [TapToPay] reset() called.")
        receipt = nil
        errorMessage = nil
        showReceipt = false
        statusMessage = "Ready to take a payment."
    }
}



//Short answer: no — test mode does not reject real cards. Test mode just means no real money moves. It doesn't decline a card for being real. Let me untangle what's actually happening, because there are two separate things being conflated.
//
//1. "Test mode is on" — but where?
//The "test mode" toggle in your Stripe Dashboard is irrelevant right now, because your local backend never talks to Stripe at all. It's in MOCK mode — your own log proves it:
//
//{"message":"Mock location.","data":{"location_id":"tml_mock_location"}}
//That tml_mock_location and the placeholder token are fake values from your Node server, not from Stripe. So no card — real or test — is reaching Stripe. Nothing can approve or decline because Stripe isn't involved yet. That's why it hangs on "Processing." You need a real sk_test_ key in the backend first.
//
//2. What test mode actually does with a real card
//Once you do have a real sk_test_ key, here's the truth:
//
//Test mode never charges your real card. No money moves, ever. Your UBL card is safe.
//It does not auto-decline a real card. Test mode isn't a fraud check — it's a sandbox. A real card tapped in a test-mode reader is processed as a simulated transaction and typically succeeds as a fake payment, not a rejection.
//With the Simulated reader (ON), your real card is never even read. The simulated reader injects a fake test card (Visa 4242) regardless of what you tap. So tapping your UBL card does nothing — you'd get a fake success.
//3. How to actually get a DECLINE (the thing you want to test)
//You don't decline by tapping a "wrong" real card. You use Stripe's simulated declined test card. With the simulated reader you set it in code before collecting:
//
//Terminal.shared.simulatorConfiguration.simulatedCard =
//    SimulatedCard(type: .chargeDeclined)   // or .chargeDeclinedInsufficientFunds, etc.
//Then the flow runs all the way to confirmPaymentIntent, which returns a real decline error, and your error UI shows it.
//
//The bottom line for your setup
//Real physical Tap to Pay (Simulated reader OFF) won't work for a Pakistan Stripe account — country not supported. Set that aside.
//To test approve and decline properly: add a real sk_test_ key, turn Simulated reader ON, and I'll wire a toggle that picks a normal test card vs a declined test card so your real error screen fires.
//Want me to add that "simulate approved / declined card" control to the simulated-reader flow? I'll need you to drop in the sk_test_ key (or set it yourself) so it can reach Stripe. Right now, with the mock backend, no card behavior is real either way.
//
//it means i have to add real live back end api right?
//then i make it live mode then i test the real card right?
//
//Not quite — you're mixing up two different things, and one of them could cost you real money. Let me separate them clearly.
//
//"Real backend" ≠ "live mode"
//These are independent:
//
//Mock vs real backend — right now your Node server is mock (it never calls Stripe). You need it to actually call Stripe using a secret key. ✅ Yes, this part you need.
//Test mode vs live mode — this is just which secret key you use:
//sk_test_… → test mode: real Stripe calls, but no real money ever moves.
//sk_live_… → live mode: real charges, real money leaves the card.
//So a "real backend" can run in test mode. You do not need live mode to test.
//
//You do NOT need live mode to test
//Test mode (sk_test_) exercises the entire real flow — connection token, payment intent, collect, confirm, approve, decline, receipt — with zero money movement. That's exactly what test mode is for.
//
//⚠️ Do not switch to live mode and tap your real UBL card "to test." In live mode that's a genuine charge — real money gets debited. Live mode is for real customers paying you, not for testing.
//
//The part that matters most for you
//Even if you go live, tapping a real card still won't work, because:
//
//Tap to Pay on iPhone via Stripe is not available for Pakistan-based Stripe accounts — in test or live mode.
//
//This is an Apple/Stripe country restriction, not a code or mode problem. Going live does not unlock real physical card tapping for a Pakistan account.
//
//So what can you actually do?
//Goal    Path
//Test the full flow (approve + decline) safely    sk_test_ key + Simulated reader ON → I add an approve/decline switch
//Tap a real physical card    ❌ Not possible on a Pakistan Stripe account, any mode
//Take real money later    Only if your Stripe account is in a Tap-to-Pay-supported country
//Bottom line: add a real backend in test mode (sk_test_), keep the simulated reader on, and you can test everything including a real decline. Real physical card taps aren't available to your account regardless of mode.
//
//Want me to double-check the current supported-country list for Tap to Pay on iPhone (in case it's changed), and add the approve/decline switch to the simulated flow? For the latter I just need you to drop in the sk_test_ key.
//
//my stripe account is from USA
//
//That changes the picture — good. The US is a supported country for Tap to Pay on iPhone, so real physical card tapping can work for your account. My earlier "not supported" note was based on the Pakistan assumption; scratch that.
//
//Here's the corrected, accurate situation.
//
//Yes, real Tap to Pay is possible now — but you still need 3 things
//Real backend with a Stripe secret key — replace mock. Use sk_test_ first (see below).
//Apple's Tap to Pay entitlement — com.apple.developer.proximity-reader.payment.acceptance added to your App ID in the Apple Developer portal, plus an entitlements file in the project. Signing won't include Tap to Pay until Apple grants this.
//Physical iPhone XS+ / iOS 16.7+, signed into iCloud.
//You still do NOT need live mode to test a real card
//This is the key correction to your plan:
//
//In test mode (sk_test_) with the real Tap to Pay reader, you can tap your real UBL card — Stripe reads it (you'll get the real brand + last4) but does not charge it. No money moves. This is the safe, correct way to test with a real card.
//It will not auto-decline just because it's a real card. In test mode it processes as a test success. To see a decline you use Stripe's test decline triggers.
//Only go live mode (sk_live_) when you're ready to take real money from real customers — not for testing.
//So: test mode + real card + real reader = real tap, real card details, zero money. That's what you want.
//
//One likely gotcha for your device ⚠️
//Your logs show the phone is set to Pakistan (en-PK, timezone PKT). Apple's Tap to Pay on iPhone also checks the device's region, not just your Stripe account. You may need to set the iPhone's region to United States (Settings → General → Language & Region) for the real reader to initialize. The Stripe account being US is necessary but the device region matters too.
//
//Next steps I can do now
//Create the MyTon.entitlements file with the Tap to Pay entitlement and wire it into the project (you'll still need to enable the capability on your App ID in the Apple portal — I'll give exact steps).
//Add a test approve / decline switch so you can verify both outcomes.
//Both need the backend reaching Stripe, so I need your sk_test_ key (test-only, can't move money) pasted here, or set it yourself:
//
//cd ~/Desktop/eventFun && STRIPE_SECRET_KEY=sk_test_xxx npm start
//Want me to add the entitlement file + wire it up now, and set the backend to use your sk_test_ key?
//
//help me do this
//reate the MyTon.entitlements file with the Tap to Pay entitlement and wire it into the project (you'll still need to enable the capability on your App ID in the Apple portal — I'll give exact steps).
//
//here is my key test key
//pk_test_51Qwl1iRqxsUs2xn5CMZtyO1Ls7Dif8tkVLhRAkBJzkT9blNTryEMuzjBDwRA31ZbrImAdHFGB1dmpa1HcrXh9I5D002RcuZrAn
//
//First, an important catch on the key: that's a publishable key (pk_test_), not the secret key. The backend needs the secret key (sk_test_…) to mint connection tokens and create payment intents — a publishable key can't do that (and it's the same placeholder that's already in there, which is why it stays in mock mode). More on that below.
//
//Let me do the entitlements work now, since that doesn't need the key.
//
//Created
//MyTon.entitlements
//+8
//-0
//Now wire it into both build configs by setting CODE_SIGN_ENTITLEMENTS. Let me find a good anchor in the pbxproj.
//
//Found anchors for entitlements setting
//Both configs have CODE_SIGN_STYLE = Automatic;. Let me add the entitlements setting before each.
//
//
//Read a file, edited a file
//Let me verify the project still parses and the entitlements setting is picked up.
//
//Confirmed entitlements setting resolves
//Done — the entitlement is created and wired in. CODE_SIGN_ENTITLEMENTS now resolves to MyTon/MyTon.entitlements.
//
//What I did
//Created MyTon.entitlements with the Tap to Pay entitlement (com.apple.developer.proximity-reader.payment.acceptance).
//Wired it into both build configs (Debug + Release) in the project.
//⚠️ Important: this will break device signing until Apple grants it
//This is a restricted entitlement. Until Apple approves it for your App ID, building to a physical device will fail with something like "provisioning profile doesn't include the com.apple.developer.proximity-reader.payment.acceptance entitlement."
//
//Escape hatch — to keep testing the simulated/mock flow on your device before the grant comes through, temporarily disable it: in Xcode → target MyTon → Build Settings → search "entitlements" → clear Code Signing Entitlements (set it back to MyTon/MyTon.entitlements once granted). Or just tell me and I'll comment it out.
//
//Exact steps to get the entitlement granted
//Request it from Apple (this is the gate): fill out Apple's form →
//https://developer.apple.com/contact/request/tap-to-pay-on-iphone/
//Provide your Team ID (PUB225UV6R) and bundle ID (com.ai.liveactnNavstrpracticeton.MyTon). This is a US-account feature — since your Stripe account is US, you're eligible.
//Wait for Apple's approval (can take a few days). They attach the capability to your Developer account.
//Add the capability in Xcode: open MyTon.xcworkspace → select the MyTon target → Signing & Capabilities → + Capability → Tap to Pay on iPhone. With Automatic signing, Xcode regenerates the provisioning profile including the entitlement.
//Build to your physical iPhone (XS+, iOS 16.7+, signed into iCloud, device region set to United States).
//Now the blocker on the key 🔑
//The key you pasted is a publishable key:
//
//pk_test_51Qwl...   ← publishable (safe to embed in apps, but can't mint tokens)
//The backend needs the secret key, which looks like:
//
//sk_test_51Qwl...   ← secret (this is what the server uses)
//Find it in Stripe Dashboard → Developers → API keys → "Secret key" → Reveal test key (make sure the Test mode switch at the top is on). It starts with sk_test_.
//
//Paste the sk_test_… key here (or run cd ~/Desktop/eventFun && STRIPE_SECRET_KEY=sk_test_xxx npm start yourself), and I'll verify the server flips to REAL mode and mints a real connection token + card-present intent. That's the last piece before the real flow runs.
//
//
//
