//
//  TapToPayView.swift
//  MyTon
//
//  The Tap to Pay screen.
//

import SwiftUI

struct TapToPayView: View {
    @StateObject private var viewModel = TapToPayViewModel()
    @ObservedObject private var terminal = TerminalManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    amountCard

                    // Error banner shown when a payment fails.
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    payButton

                    settingsCard

                    Text(viewModel.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if viewModel.useRealTerminal {
                        Text(terminal.readerStatus)
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                .padding()
            }
            .navigationTitle("Tap to Pay")
            .navigationDestination(isPresented: $viewModel.showReceipt) {
                if let receipt = viewModel.receipt {
                    ReceiptView(receipt: receipt) {
                        viewModel.reset()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Accept a contactless payment")
                .font(.headline)
            Text("Enter an amount and hold the customer's card or phone near the top of your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(viewModel.currency.uppercased())
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var payButton: some View {
        Button {
            Task { await viewModel.startPayment() }
        } label: {
            HStack {
                if viewModel.isProcessing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "creditcard.fill")
                }
                Text(viewModel.isProcessing ? "Processing…" : "Tap to Pay")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(viewModel.isProcessing)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use real Stripe Terminal", isOn: $viewModel.useRealTerminal)
            if viewModel.useRealTerminal {
                Toggle("Simulated reader (test without a real card)", isOn: $viewModel.useSimulatedReader)
                Text(viewModel.useSimulatedReader
                     ? "Uses Stripe's simulated reader — full real flow, no entitlement or physical card needed."
                     : "Real Tap to Pay: needs the entitlement + a physical iPhone. Waits for an actual card tap.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Simulate a declined card", isOn: $viewModel.simulateFailure)
                Text("Mock flow — no card is read; the receipt is fake test data.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.12))
        .foregroundStyle(.red)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    TapToPayView()
}
