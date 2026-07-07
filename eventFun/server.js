const express = require("express");
const Stripe = require("stripe");

const app = express();

// ---- Config -------------------------------------------------------------
// PASTE YOUR STRIPE SECRET KEY HERE (starts with "sk_test_" for testing).
// While this is not a real secret key the server runs in MOCK mode so the
// app keeps working, but real Tap to Pay needs a real sk_ key.
const STRIPE_SECRET_KEY =
  process.env.STRIPE_SECRET_KEY ||
  "pk_test_51Qwl1iRqxsUs2xn5CMZtyO1Ls7Dif8tkVLhRAkBJzkT9blNTryEMuzjBDwRA31ZbrImAdHFGB1dmpa1HcrXh9I5D002RcuZrAn";

const PORT = process.env.PORT || 3000;
const MERCHANT_NAME = "eventFun";

// Real mode is enabled only when a proper secret key is configured.
const REAL_MODE = STRIPE_SECRET_KEY.startsWith("sk_");
const stripe = REAL_MODE ? new Stripe(STRIPE_SECRET_KEY) : null;

// Cache a Terminal Location id (Tap to Pay needs one to connect a reader).
let cachedLocationId = process.env.STRIPE_LOCATION_ID || null;

// In-memory store for the MOCK flow so a receipt can be looked up.
const payments = {};

console.log(
  REAL_MODE
    ? "✅ Stripe REAL mode enabled (using sk_ key)."
    : "⚠️  Stripe MOCK mode (no sk_ key set). Real Tap to Pay will NOT work until you add a secret key."
);

// ---- Middleware ---------------------------------------------------------
app.use(express.json());
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// ---- Helpers ------------------------------------------------------------
function randomId(prefix) {
  return prefix + Math.random().toString(36).slice(2, 14);
}
function formatAmount(amount, currency) {
  const major = (Number(amount) / 100).toFixed(2);
  return `${currency.toUpperCase()} ${major}`;
}

// Create (once) or reuse a Terminal Location for connecting the reader.
async function getOrCreateLocationId() {
  if (cachedLocationId) return cachedLocationId;
  const existing = await stripe.terminal.locations.list({ limit: 1 });
  if (existing.data.length > 0) {
    cachedLocationId = existing.data[0].id;
    return cachedLocationId;
  }
  const location = await stripe.terminal.locations.create({
    display_name: MERCHANT_NAME,
    address: {
      line1: "1 Test Street",
      city: "London",
      country: "GB",
      postal_code: "WC2N 5DU",
    },
  });
  cachedLocationId = location.id;
  return cachedLocationId;
}

// ---- Routes -------------------------------------------------------------

app.get("/", (_req, res) => {
  res.json({
    success: true,
    message: `eventFun API is running (${REAL_MODE ? "REAL" : "MOCK"} mode).`,
  });
});

// POST /connection_token — Stripe Terminal / Tap to Pay bootstrap.
app.post("/connection_token", async (_req, res) => {
  try {
    if (REAL_MODE) {
      const token = await stripe.terminal.connectionTokens.create();
      return res.json({
        success: true,
        message: "Connection token generated successfully.",
        data: { secret: token.secret },
      });
    }
    // MOCK
    res.json({
      success: true,
      message: "Connection token generated successfully.",
      data: { secret: STRIPE_SECRET_KEY },
    });
  } catch (err) {
    console.error("connection_token error:", err.message);
    res.status(500).json({ success: false, message: err.message, data: null });
  }
});

// GET /terminal_location — location id the iOS app uses to connect the reader.
app.get("/terminal_location", async (_req, res) => {
  try {
    if (!REAL_MODE) {
      return res.json({
        success: true,
        message: "Mock location.",
        data: { location_id: "tml_mock_location" },
      });
    }
    const locationId = await getOrCreateLocationId();
    res.json({
      success: true,
      message: "Location fetched successfully.",
      data: { location_id: locationId },
    });
  } catch (err) {
    console.error("terminal_location error:", err.message);
    res.status(500).json({ success: false, message: err.message, data: null });
  }
});

// POST /create_payment_intent — card-present PaymentIntent for Tap to Pay.
// Body: { "amount": 2500, "currency": "usd" }  (amount in the smallest unit)
app.post("/create_payment_intent", async (req, res) => {
  const { amount, currency } = req.body || {};

  if (amount === undefined || amount === null || isNaN(Number(amount)) || Number(amount) <= 0) {
    return res.status(400).json({
      success: false,
      message: "Invalid request. 'amount' is required and must be a positive number.",
      data: null,
    });
  }
  const resolvedCurrency = (currency || "usd").toLowerCase();

  try {
    if (REAL_MODE) {
      const intent = await stripe.paymentIntents.create({
        amount: Number(amount),
        currency: resolvedCurrency,
        payment_method_types: ["card_present"],
        capture_method: "automatic",
      });
      return res.json({
        success: true,
        message: "Payment intent created successfully.",
        data: {
          id: intent.id,
          amount: intent.amount,
          currency: intent.currency,
          status: intent.status,
          client_secret: intent.client_secret,
        },
      });
    }

    // MOCK
    const intentId = randomId("pi_");
    payments[intentId] = {
      id: intentId,
      amount: Number(amount),
      currency: resolvedCurrency,
      status: "requires_payment_method",
      client_secret: intentId + "_secret_" + Math.random().toString(36).slice(2, 14),
      created: Date.now(),
    };
    res.json({
      success: true,
      message: "Payment intent created successfully.",
      data: payments[intentId],
    });
  } catch (err) {
    console.error("create_payment_intent error:", err.message);
    res.status(500).json({ success: false, message: err.message, data: null });
  }
});

// POST /capture_payment — MOCK-only helper (real flow confirms on device).
app.post("/capture_payment", (req, res) => {
  const { payment_intent_id, simulate_failure } = req.body || {};
  if (!payment_intent_id) {
    return res.status(400).json({ success: false, message: "Invalid request. 'payment_intent_id' is required.", data: null });
  }
  const record = payments[payment_intent_id];
  if (!record) {
    return res.status(404).json({ success: false, message: "Payment intent not found.", data: null });
  }
  if (simulate_failure === true) {
    record.status = "failed";
    return res.status(402).json({
      success: false,
      message: "Payment failed. The card was declined.",
      data: { code: "card_declined", decline_code: "generic_decline", payment_intent_id: record.id },
    });
  }
  record.status = "succeeded";
  record.receipt = {
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
  res.json({ success: true, message: "Payment captured successfully.", data: record.receipt });
});

// POST /receipt — MOCK-only receipt lookup.
app.post("/receipt", (req, res) => {
  const { payment_intent_id } = req.body || {};
  const record = payments[payment_intent_id];
  if (!record || !record.receipt) {
    return res.status(404).json({ success: false, message: "Receipt not found for this payment.", data: null });
  }
  res.json({ success: true, message: "Receipt fetched successfully.", data: record.receipt });
});

// ---- Start --------------------------------------------------------------
app.listen(PORT, "0.0.0.0", () => {
  console.log(`eventFun API listening on http://0.0.0.0:${PORT}`);
});
