const express = require("express");

const app = express();

// ---- Config -------------------------------------------------------------
// Replace this later with your real Stripe secret key.
const STRIPE_SECRET_KEY =
  "pk_test_51Qwl1iRqxsUs2xn5CMZtyO1Ls7Dif8tkVLhRAkBJzkT9blNTryEMuzjBDwRA31ZbrImAdHFGB1dmpa1HcrXh9I5D002RcuZrAn";

const PORT = process.env.PORT || 3000;
const MERCHANT_NAME = "eventFun";

// In-memory store so a receipt can be looked up after a payment.
const payments = {}; // { [paymentIntentId]: paymentRecord }

// ---- Middleware ---------------------------------------------------------
// Parse JSON bodies. All APIs are public (no auth token required).
app.use(express.json());

// Simple request logger so you can see calls from the iOS app in the terminal.
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// ---- Helpers ------------------------------------------------------------
function randomId(prefix) {
  return prefix + Math.random().toString(36).slice(2, 14);
}

function formatAmount(amount, currency) {
  // amount is in the smallest unit (cents). Present a human-readable string.
  const major = (Number(amount) / 100).toFixed(2);
  return `${currency.toUpperCase()} ${major}`;
}

// ---- Routes -------------------------------------------------------------

// Health check
app.get("/", (_req, res) => {
  res.json({ success: true, message: "eventFun API is running." });
});

// POST /connection_token
// Used by the iOS app (Tap to Pay / Stripe Terminal) to get a connection token.
app.post("/connection_token", (_req, res) => {
  res.json({
    success: true,
    message: "Connection token generated successfully.",
    data: {
      secret: STRIPE_SECRET_KEY,
    },
  });
});

// POST /create_payment_intent
// Body (valid JSON): { "amount": 1000, "currency": "usd" }
// amount is in the smallest currency unit (e.g. cents).
app.post("/create_payment_intent", (req, res) => {
  const { amount, currency } = req.body || {};

  if (amount === undefined || amount === null || isNaN(Number(amount)) || Number(amount) <= 0) {
    return res.status(400).json({
      success: false,
      message: "Invalid request. 'amount' is required and must be a positive number.",
      data: null,
    });
  }

  const resolvedCurrency = (currency || "usd").toLowerCase();
  const intentId = randomId("pi_");
  const clientSecret = intentId + "_secret_" + Math.random().toString(36).slice(2, 14);

  payments[intentId] = {
    id: intentId,
    amount: Number(amount),
    currency: resolvedCurrency,
    status: "requires_payment_method",
    client_secret: clientSecret,
    created: Date.now(),
  };

  res.json({
    success: true,
    message: "Payment intent created successfully.",
    data: payments[intentId],
  });
});

// POST /capture_payment
// Called after the card is tapped to finalize the charge.
// Body: { "payment_intent_id": "pi_xxx", "simulate_failure": false }
// On success it returns a receipt. On failure it returns an error the app shows.
app.post("/capture_payment", (req, res) => {
  const { payment_intent_id, simulate_failure } = req.body || {};

  if (!payment_intent_id) {
    return res.status(400).json({
      success: false,
      message: "Invalid request. 'payment_intent_id' is required.",
      data: null,
    });
  }

  const record = payments[payment_intent_id];
  if (!record) {
    return res.status(404).json({
      success: false,
      message: "Payment intent not found.",
      data: null,
    });
  }

  // Simulate a declined / failed payment so the app can show the error UI.
  if (simulate_failure === true) {
    record.status = "failed";
    return res.status(402).json({
      success: false,
      message: "Payment failed. The card was declined.",
      data: {
        code: "card_declined",
        decline_code: "generic_decline",
        payment_intent_id: record.id,
      },
    });
  }

  // Mark as paid and build a receipt.
  record.status = "succeeded";
  const receipt = {
    receipt_id: randomId("rcpt_"),
    payment_intent_id: record.id,
    merchant: MERCHANT_NAME,
    amount: record.amount,
    currency: record.currency,
    amount_display: formatAmount(record.amount, record.currency),
    status: "succeeded",
    card_brand: "Visa",
    card_last4: "4242",
    date: new Date().toISOString(),
  };
  record.receipt = receipt;

  res.json({
    success: true,
    message: "Payment captured successfully.",
    data: receipt,
  });
});

// POST /receipt
// Body: { "payment_intent_id": "pi_xxx" }
// Returns the receipt for a completed payment.
app.post("/receipt", (req, res) => {
  const { payment_intent_id } = req.body || {};

  const record = payments[payment_intent_id];
  if (!record || !record.receipt) {
    return res.status(404).json({
      success: false,
      message: "Receipt not found for this payment.",
      data: null,
    });
  }

  res.json({
    success: true,
    message: "Receipt fetched successfully.",
    data: record.receipt,
  });
});

// ---- Start --------------------------------------------------------------
app.listen(PORT, "0.0.0.0", () => {
  console.log(`eventFun API listening on http://0.0.0.0:${PORT}`);
});
