//
//  StripeConnectionTokenProvider.swift
//  MyTon
//
//  Bridges the eventFun `/connection_token` API to the Stripe Terminal SDK.
//
//  This file is guarded by `#if canImport(StripeTerminal)` so the project
//  keeps compiling before `pod install`. After the Stripe pods are added it
//  automatically becomes an active `ConnectionTokenProvider`.
//
//  To start Tap to Pay on a real device, in your App startup call:
//      Terminal.setTokenProvider(StripeConnectionTokenProvider())
//  then discover + connect a Tap to Pay reader and collect a payment.
//

import Foundation

#if canImport(StripeTerminal)
import StripeTerminal

final class StripeConnectionTokenProvider: NSObject, ConnectionTokenProvider {
    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        print("🔌 [StripeTerminal] fetchConnectionToken called by SDK…")
        Task {
            do {
                let token = try await APIClient.shared.fetchConnectionToken()
                print("✅ [StripeTerminal] connection token delivered to SDK.")
                completion(token.secret, nil)
            } catch {
                print("❌ [StripeTerminal] connection token failed: \(error.localizedDescription)")
                completion(nil, error)
            }
        }
    }
}
#endif
