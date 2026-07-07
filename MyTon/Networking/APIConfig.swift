//
//  APIConfig.swift
//  MyTon
//
//  Central place for the backend configuration.
//

import Foundation

enum APIConfig {
    /// Base URL of the local eventFun Node.js server.
    /// Your Mac's LAN IP so a physical iPhone on the same Wi-Fi can reach it.
    /// Use "http://localhost:3000" if you run on the iOS Simulator.
    static let baseURL = URL(string: "http://192.168.100.191:3000")!

    enum Path {
        static let connectionToken = "connection_token"
        static let createPaymentIntent = "create_payment_intent"
        static let capturePayment = "capture_payment"
        static let receipt = "receipt"
    }
}
