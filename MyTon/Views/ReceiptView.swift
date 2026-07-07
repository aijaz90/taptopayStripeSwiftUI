//
//  ReceiptView.swift
//  MyTon
//
//  Displays the receipt returned by the API after a successful payment.
//

import SwiftUI

struct ReceiptView: View {
    let receipt: ReceiptData
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Payment Successful")
                        .font(.title2.weight(.bold))
                    Text(receipt.merchant)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                Text(receipt.amountDisplay)
                    .font(.system(size: 40, weight: .bold, design: .rounded))

                VStack(spacing: 0) {
                    row("Status", receipt.status.capitalized)
                    Divider()
                    row("Card", "\(receipt.cardBrand) •••• \(receipt.cardLast4)")
                    Divider()
                    row("Receipt ID", receipt.receiptId)
                    Divider()
                    row("Payment ID", receipt.paymentIntentId)
                    Divider()
                    row("Date", formattedDate(receipt.date))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button(action: onDone) {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .navigationTitle("Receipt")
        .navigationBarBackButtonHidden(true)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 8)
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ReceiptView(
            receipt: ReceiptData(
                receiptId: "rcpt_demo123",
                paymentIntentId: "pi_demo123",
                merchant: "eventFun",
                amount: 2500,
                currency: "usd",
                amountDisplay: "USD 25.00",
                status: "succeeded",
                cardBrand: "Visa",
                cardLast4: "4242",
                date: "2026-07-07T16:40:33.566Z"
            ),
            onDone: {}
        )
    }
}
