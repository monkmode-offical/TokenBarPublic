#!/usr/bin/env node

import { createServer } from "node:http";
import { randomBytes, createHmac, timingSafeEqual } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const config = {
    host: process.env.HOST ?? "0.0.0.0",
    port: Number.parseInt(process.env.PORT ?? "8787", 10),
    stripeSecretKey: process.env.STRIPE_SECRET_KEY ?? "",
    stripeWebhookSecret: process.env.STRIPE_WEBHOOK_SECRET ?? "",
    stripePriceId: process.env.STRIPE_PRICE_ID ?? "price_1T5K9zHJXHN3Z05HRzvm7Ief",
    successURL: process.env.STRIPE_SUCCESS_URL
        ?? "https://tokenbar.site/checkout/success?session_id={CHECKOUT_SESSION_ID}",
    cancelURL: process.env.STRIPE_CANCEL_URL ?? "https://tokenbar.site/checkout/cancel",
    appBaseURL: process.env.APP_BASE_URL ?? "https://tokenbar.site",
    maxDevicesPerLicense: Number.parseInt(process.env.LICENSE_MAX_DEVICES ?? "1", 10),
    dataPath: process.env.LICENSE_DB_PATH ?? path.join(__dirname, "data", "licenses.json"),
    allowedOrigin: process.env.LICENSE_ALLOWED_ORIGIN ?? "https://tokenbar.site",
};

const jsonHeaders = {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
};

let db = null;
let writeQueue = Promise.resolve();

function nowISO() {
    return new Date().toISOString();
}

function normalizeLicenseKey(value) {
    return String(value ?? "")
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9-]/g, "");
}

function sanitizeEmail(value) {
    const trimmed = String(value ?? "").trim().toLowerCase();
    return trimmed.length > 0 && trimmed.length <= 254 ? trimmed : undefined;
}

function sanitizeDeviceId(value) {
    const trimmed = String(value ?? "").trim();
    if (!trimmed) {
        return undefined;
    }
    if (trimmed.length > 128) {
        throw new Error("device_id too long");
    }
    return trimmed;
}

function ensureDbShape(input) {
    const base = input && typeof input === "object" ? input : {};
    return {
        version: 1,
        licenses: base.licenses && typeof base.licenses === "object" ? base.licenses : {},
        checkoutToLicense: base.checkoutToLicense && typeof base.checkoutToLicense === "object" ? base.checkoutToLicense : {},
        paymentIntentToLicense:
            base.paymentIntentToLicense && typeof base.paymentIntentToLicense === "object"
                ? base.paymentIntentToLicense
                : {},
        chargeToLicense: base.chargeToLicense && typeof base.chargeToLicense === "object" ? base.chargeToLicense : {},
    };
}

async function loadDb() {
    if (db) {
        return db;
    }

    try {
        const raw = await fs.readFile(config.dataPath, "utf8");
        db = ensureDbShape(JSON.parse(raw));
        return db;
    } catch (error) {
        if (error && error.code !== "ENOENT") {
            throw error;
        }
        db = ensureDbShape({});
        await saveDb();
        return db;
    }
}

async function saveDb() {
    await fs.mkdir(path.dirname(config.dataPath), { recursive: true });
    const body = JSON.stringify(db, null, 2);
    const tmpPath = `${config.dataPath}.tmp`;
    await fs.writeFile(tmpPath, body, "utf8");
    await fs.rename(tmpPath, config.dataPath);
}

function withWriteLock(task) {
    const run = async () => {
        await loadDb();
        const result = await task();
        await saveDb();
        return result;
    };
    writeQueue = writeQueue.then(run, run);
    return writeQueue;
}

function makeLicenseKey() {
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    const bytes = randomBytes(16);
    const chars = [];
    for (let index = 0; index < bytes.length; index += 1) {
        chars.push(alphabet[bytes[index] % alphabet.length]);
    }
    const body = [
        chars.slice(0, 4).join(""),
        chars.slice(4, 8).join(""),
        chars.slice(8, 12).join(""),
        chars.slice(12, 16).join(""),
    ].join("-");
    return `TB-${body}`;
}

function jsonResponse(statusCode, payload, extraHeaders = {}) {
    return {
        statusCode,
        headers: {
            ...jsonHeaders,
            ...extraHeaders,
        },
        body: JSON.stringify(payload),
    };
}

function routeNotFound() {
    return jsonResponse(404, { error: "not_found" });
}

function parseStripeSignatureHeader(header) {
    const values = {
        t: "",
        v1: [],
    };
    for (const part of String(header ?? "").split(",")) {
        const [rawKey, rawValue] = part.split("=");
        const key = String(rawKey ?? "").trim();
        const value = String(rawValue ?? "").trim();
        if (!key || !value) {
            continue;
        }
        if (key === "t") {
            values.t = value;
        } else if (key === "v1") {
            values.v1.push(value);
        }
    }
    return values;
}

function secureCompareHex(leftHex, rightHex) {
    const left = Buffer.from(String(leftHex ?? ""), "hex");
    const right = Buffer.from(String(rightHex ?? ""), "hex");
    if (left.length === 0 || right.length === 0 || left.length !== right.length) {
        return false;
    }
    return timingSafeEqual(left, right);
}

function verifyStripeWebhookSignature({ payload, signatureHeader }) {
    if (!config.stripeWebhookSecret) {
        throw new Error("Missing STRIPE_WEBHOOK_SECRET");
    }

    const parsed = parseStripeSignatureHeader(signatureHeader);
    if (!parsed.t || parsed.v1.length === 0) {
        throw new Error("Invalid stripe-signature header");
    }

    const timestampSeconds = Number.parseInt(parsed.t, 10);
    if (!Number.isFinite(timestampSeconds)) {
        throw new Error("Invalid stripe-signature timestamp");
    }

    const toleranceSeconds = 300;
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (Math.abs(nowSeconds - timestampSeconds) > toleranceSeconds) {
        throw new Error("Webhook signature timestamp outside tolerance window");
    }

    const signedPayload = `${parsed.t}.${payload}`;
    const expected = createHmac("sha256", config.stripeWebhookSecret)
        .update(signedPayload, "utf8")
        .digest("hex");

    const isValid = parsed.v1.some((candidate) => secureCompareHex(candidate, expected));
    if (!isValid) {
        throw new Error("Invalid webhook signature");
    }
}

function encodeForm(data) {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(data)) {
        if (value === undefined || value === null) {
            continue;
        }
        params.append(key, String(value));
    }
    return params.toString();
}

async function stripeRequest({ method, pathName, body, contentType = "application/x-www-form-urlencoded" }) {
    if (!config.stripeSecretKey) {
        throw new Error("Missing STRIPE_SECRET_KEY");
    }

    const endpoint = `https://api.stripe.com${pathName}`;
    const response = await fetch(endpoint, {
        method,
        headers: {
            Authorization: `Bearer ${config.stripeSecretKey}`,
            ...(method === "POST" ? { "content-type": contentType } : {}),
        },
        body: method === "POST" ? body : undefined,
    });

    const parsed = await response.json().catch(() => ({}));
    if (!response.ok) {
        const message = parsed?.error?.message ?? `Stripe request failed (${response.status})`;
        const error = new Error(message);
        error.statusCode = response.status;
        error.details = parsed;
        throw error;
    }

    return parsed;
}

async function stripeGetCheckoutSession(sessionId) {
    const safeId = encodeURIComponent(sessionId);
    return stripeRequest({ method: "GET", pathName: `/v1/checkout/sessions/${safeId}` });
}

async function stripeGetCheckoutLineItems(sessionId) {
    const safeId = encodeURIComponent(sessionId);
    return stripeRequest({ method: "GET", pathName: `/v1/checkout/sessions/${safeId}/line_items?limit=100` });
}

async function stripeGetPaymentIntent(paymentIntentId) {
    const safeId = encodeURIComponent(paymentIntentId);
    return stripeRequest({ method: "GET", pathName: `/v1/payment_intents/${safeId}?expand[]=latest_charge` });
}

function licenseForKey(licenseKey) {
    return db.licenses[licenseKey];
}

function updateLicenseIndexes(licenseKey, { checkoutSessionId, paymentIntentId, chargeId }) {
    if (checkoutSessionId) {
        db.checkoutToLicense[checkoutSessionId] = licenseKey;
    }
    if (paymentIntentId) {
        db.paymentIntentToLicense[paymentIntentId] = licenseKey;
    }
    if (chargeId) {
        db.chargeToLicense[chargeId] = licenseKey;
    }
}

function ensureDeviceBound(license, deviceId) {
    if (!deviceId) {
        return {
            ok: false,
            reason: "missing_device",
            message: "device_id is required for 1-device license enforcement",
        };
    }

    const existing = license.devices.find((entry) => entry.deviceId === deviceId);
    if (existing) {
        existing.lastSeenAt = nowISO();
        return { ok: true };
    }

    if (license.devices.length >= license.maxDevices) {
        return {
            ok: false,
            reason: "device_limit",
            message: `This license is already active on ${license.maxDevices} device${license.maxDevices === 1 ? "" : "s"}.`,
        };
    }

    const timestamp = nowISO();
    license.devices.push({
        deviceId,
        firstSeenAt: timestamp,
        lastSeenAt: timestamp,
    });
    return { ok: true };
}

async function getPaidCheckoutContext(sessionId) {
    const session = await stripeGetCheckoutSession(sessionId);
    const lineItems = await stripeGetCheckoutLineItems(sessionId);

    if (session.mode !== "payment") {
        throw new Error("Checkout session is not payment mode");
    }
    if (session.payment_status !== "paid") {
        throw new Error("Checkout session is not paid");
    }

    const matchingLineItem = (lineItems.data ?? []).find((item) => item?.price?.id === config.stripePriceId);
    if (!matchingLineItem) {
        throw new Error("Checkout session does not include the expected price id");
    }

    let paymentIntentId;
    if (typeof session.payment_intent === "string") {
        paymentIntentId = session.payment_intent;
    } else if (session.payment_intent && typeof session.payment_intent === "object") {
        paymentIntentId = session.payment_intent.id;
    }

    let chargeId;
    if (paymentIntentId) {
        const paymentIntent = await stripeGetPaymentIntent(paymentIntentId);
        if (typeof paymentIntent.latest_charge === "string") {
            chargeId = paymentIntent.latest_charge;
        } else if (paymentIntent.latest_charge && typeof paymentIntent.latest_charge === "object") {
            chargeId = paymentIntent.latest_charge.id;
        }
    }

    const email = sanitizeEmail(
        session.customer_details?.email
        ?? session.customer_email
        ?? session.customer?.email
        ?? undefined,
    );

    return {
        session,
        paymentIntentId,
        chargeId,
        email,
    };
}

function buildVerifyResponse(license, valid, overrides = {}) {
    return {
        valid,
        status: valid ? "active" : license?.status ?? "invalid",
        reason: overrides.reason,
        message: overrides.message,
        max_devices: license?.maxDevices ?? config.maxDevicesPerLicense,
        active_devices: license?.devices?.length ?? 0,
        license_key: license?.licenseKey,
    };
}

function revokeLicense(licenseKey, reason) {
    const license = licenseForKey(licenseKey);
    if (!license) {
        return false;
    }
    license.status = "revoked";
    license.revokedAt = nowISO();
    license.revokedReason = reason;
    license.updatedAt = nowISO();
    return true;
}

async function readRequestBody(req, maxBytes = 1_000_000) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        let total = 0;

        req.on("data", (chunk) => {
            total += chunk.length;
            if (total > maxBytes) {
                reject(new Error("Request body too large"));
                req.destroy();
                return;
            }
            chunks.push(chunk);
        });

        req.on("end", () => {
            resolve(Buffer.concat(chunks));
        });

        req.on("error", (error) => {
            reject(error);
        });
    });
}

function withCors(headers, origin) {
    const merged = { ...headers };
    const normalizedOrigin = String(origin ?? "").trim();
    if (config.allowedOrigin === "*") {
        merged["access-control-allow-origin"] = "*";
    } else if (normalizedOrigin && normalizedOrigin === config.allowedOrigin) {
        merged["access-control-allow-origin"] = normalizedOrigin;
        merged.vary = "Origin";
    }
    merged["access-control-allow-methods"] = "GET,POST,OPTIONS";
    merged["access-control-allow-headers"] = "content-type,stripe-signature";
    return merged;
}

function send(res, response, origin) {
    const headers = withCors(response.headers ?? {}, origin);
    res.writeHead(response.statusCode, headers);
    res.end(response.body ?? "");
}

async function handleCreateCheckoutSession(rawBody) {
    const payload = rawBody.length > 0 ? JSON.parse(rawBody.toString("utf8")) : {};
    const email = sanitizeEmail(payload.email);
    const deviceId = payload.device_id ? sanitizeDeviceId(payload.device_id) : undefined;

    const form = encodeForm({
        mode: "payment",
        success_url: config.successURL,
        cancel_url: config.cancelURL,
        "line_items[0][price]": config.stripePriceId,
        "line_items[0][quantity]": 1,
        allow_promotion_codes: true,
        customer_email: email,
        "metadata[source]": "tokenbar",
        "metadata[device_id]": deviceId,
    });

    const session = await stripeRequest({
        method: "POST",
        pathName: "/v1/checkout/sessions",
        body: form,
    });

    return jsonResponse(200, {
        checkout_url: session.url,
        session_id: session.id,
        publishable_key: process.env.STRIPE_PUBLISHABLE_KEY ?? undefined,
    });
}

async function handleIssueFromSession(rawBody) {
    const payload = rawBody.length > 0 ? JSON.parse(rawBody.toString("utf8")) : {};
    const sessionId = String(payload.session_id ?? "").trim();
    if (!sessionId) {
        return jsonResponse(400, { error: "session_id is required" });
    }

    let deviceId;
    try {
        deviceId = sanitizeDeviceId(payload.device_id);
    } catch (error) {
        return jsonResponse(400, { error: error.message });
    }

    const checkout = await getPaidCheckoutContext(sessionId);

    const result = await withWriteLock(async () => {
        let licenseKey = db.checkoutToLicense[sessionId];
        let license = licenseKey ? licenseForKey(licenseKey) : undefined;

        if (!license) {
            licenseKey = makeLicenseKey();
            while (db.licenses[licenseKey]) {
                licenseKey = makeLicenseKey();
            }
            const timestamp = nowISO();
            license = {
                licenseKey,
                status: "active",
                createdAt: timestamp,
                updatedAt: timestamp,
                revokedAt: null,
                revokedReason: null,
                maxDevices: config.maxDevicesPerLicense,
                devices: [],
                email: checkout.email,
                checkoutSessionId: sessionId,
                paymentIntentId: checkout.paymentIntentId,
                chargeId: checkout.chargeId,
            };
            db.licenses[licenseKey] = license;
        }

        license.updatedAt = nowISO();
        if (checkout.email) {
            license.email = checkout.email;
        }
        if (checkout.paymentIntentId) {
            license.paymentIntentId = checkout.paymentIntentId;
        }
        if (checkout.chargeId) {
            license.chargeId = checkout.chargeId;
        }
        updateLicenseIndexes(license.licenseKey, {
            checkoutSessionId: sessionId,
            paymentIntentId: checkout.paymentIntentId,
            chargeId: checkout.chargeId,
        });

        if (license.status !== "active") {
            return {
                statusCode: 403,
                payload: buildVerifyResponse(license, false, {
                    reason: license.revokedReason ?? "revoked",
                    message: "This license has been revoked and cannot be reissued.",
                }),
            };
        }

        const binding = ensureDeviceBound(license, deviceId);
        if (!binding.ok) {
            return {
                statusCode: 403,
                payload: buildVerifyResponse(license, false, {
                    reason: binding.reason,
                    message: binding.message,
                }),
            };
        }

        license.updatedAt = nowISO();
        return {
            statusCode: 200,
            payload: {
                license_key: license.licenseKey,
                status: license.status,
                max_devices: license.maxDevices,
                active_devices: license.devices.length,
            },
        };
    });

    return jsonResponse(result.statusCode, result.payload);
}

async function handleVerifyLicense(rawBody) {
    const payload = rawBody.length > 0 ? JSON.parse(rawBody.toString("utf8")) : {};
    const licenseKey = normalizeLicenseKey(payload.license_key);

    let deviceId;
    try {
        deviceId = sanitizeDeviceId(payload.device_id);
    } catch (error) {
        return jsonResponse(400, { error: error.message });
    }

    if (!licenseKey) {
        return jsonResponse(400, {
            ...buildVerifyResponse(undefined, false, {
                reason: "missing_license",
                message: "license_key is required",
            }),
        });
    }

    const result = await withWriteLock(async () => {
        const license = licenseForKey(licenseKey);
        if (!license) {
            return {
                statusCode: 404,
                payload: buildVerifyResponse(undefined, false, {
                    reason: "not_found",
                    message: "License key not found.",
                }),
            };
        }

        if (license.status !== "active") {
            return {
                statusCode: 403,
                payload: buildVerifyResponse(license, false, {
                    reason: license.revokedReason ?? "revoked",
                    message: "License is not active.",
                }),
            };
        }

        const binding = ensureDeviceBound(license, deviceId);
        if (!binding.ok) {
            return {
                statusCode: 403,
                payload: buildVerifyResponse(license, false, {
                    reason: binding.reason,
                    message: binding.message,
                }),
            };
        }

        license.updatedAt = nowISO();
        return {
            statusCode: 200,
            payload: buildVerifyResponse(license, true, {
                message: "License verified.",
            }),
        };
    });

    return jsonResponse(result.statusCode, result.payload);
}

async function handleStripeWebhook(rawBody, signatureHeader) {
    const payload = rawBody.toString("utf8");
    verifyStripeWebhookSignature({ payload, signatureHeader });

    const event = JSON.parse(payload);

    if (event.type === "checkout.session.completed") {
        const session = event.data?.object;
        const sessionId = String(session?.id ?? "").trim();
        if (sessionId) {
            try {
                const checkout = await getPaidCheckoutContext(sessionId);
                await withWriteLock(async () => {
                    let licenseKey = db.checkoutToLicense[sessionId];
                    let license = licenseKey ? licenseForKey(licenseKey) : undefined;
                    if (!license) {
                        licenseKey = makeLicenseKey();
                        while (db.licenses[licenseKey]) {
                            licenseKey = makeLicenseKey();
                        }
                        const timestamp = nowISO();
                        license = {
                            licenseKey,
                            status: "active",
                            createdAt: timestamp,
                            updatedAt: timestamp,
                            revokedAt: null,
                            revokedReason: null,
                            maxDevices: config.maxDevicesPerLicense,
                            devices: [],
                            email: checkout.email,
                            checkoutSessionId: sessionId,
                            paymentIntentId: checkout.paymentIntentId,
                            chargeId: checkout.chargeId,
                        };
                        db.licenses[licenseKey] = license;
                    } else {
                        license.updatedAt = nowISO();
                        if (checkout.email) {
                            license.email = checkout.email;
                        }
                        if (checkout.paymentIntentId) {
                            license.paymentIntentId = checkout.paymentIntentId;
                        }
                        if (checkout.chargeId) {
                            license.chargeId = checkout.chargeId;
                        }
                    }
                    updateLicenseIndexes(license.licenseKey, {
                        checkoutSessionId: sessionId,
                        paymentIntentId: checkout.paymentIntentId,
                        chargeId: checkout.chargeId,
                    });
                });
            } catch (error) {
                console.error("[webhook] checkout.session.completed processing failed", {
                    sessionId,
                    error: error?.message ?? String(error),
                });
            }
        }
    }

    if (event.type === "charge.refunded") {
        const charge = event.data?.object;
        const chargeId = String(charge?.id ?? "").trim();
        const paymentIntentId = String(charge?.payment_intent ?? "").trim() || undefined;
        await withWriteLock(async () => {
            const licenseKey = db.chargeToLicense[chargeId] || (paymentIntentId ? db.paymentIntentToLicense[paymentIntentId] : undefined);
            if (!licenseKey) {
                return;
            }
            revokeLicense(licenseKey, "refund");
        });
    }

    if (event.type === "charge.dispute.created") {
        const dispute = event.data?.object;
        const chargeId = String(dispute?.charge ?? "").trim();
        await withWriteLock(async () => {
            const licenseKey = db.chargeToLicense[chargeId];
            if (!licenseKey) {
                return;
            }
            revokeLicense(licenseKey, "dispute");
        });
    }

    return jsonResponse(200, { received: true });
}

const server = createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (!req.url || !req.method) {
        send(res, routeNotFound(), origin);
        return;
    }

    const method = req.method.toUpperCase();
    const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);

    if (method === "OPTIONS") {
        send(res, { statusCode: 204, headers: {}, body: "" }, origin);
        return;
    }

    try {
        if (method === "GET" && url.pathname === "/healthz") {
            send(
                res,
                jsonResponse(200, {
                    ok: true,
                    now: nowISO(),
                    price_id: config.stripePriceId,
                    max_devices: config.maxDevicesPerLicense,
                }),
                origin,
            );
            return;
        }

        if (method === "POST" && url.pathname === "/api/checkout/session") {
            const body = await readRequestBody(req);
            const response = await handleCreateCheckoutSession(body);
            send(res, response, origin);
            return;
        }

        if (method === "POST" && url.pathname === "/api/license/issue-from-session") {
            const body = await readRequestBody(req);
            const response = await handleIssueFromSession(body);
            send(res, response, origin);
            return;
        }

        if (method === "POST" && url.pathname === "/api/license/verify") {
            const body = await readRequestBody(req);
            const response = await handleVerifyLicense(body);
            send(res, response, origin);
            return;
        }

        if (method === "POST" && url.pathname === "/api/webhooks/stripe") {
            const body = await readRequestBody(req, 2_000_000);
            const signatureHeader = req.headers["stripe-signature"];
            const response = await handleStripeWebhook(body, signatureHeader);
            send(res, response, origin);
            return;
        }

        send(res, routeNotFound(), origin);
    } catch (error) {
        const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
        const message = error?.message ?? "Unexpected error";
        console.error("[license-server] request failed", {
            method,
            path: url.pathname,
            statusCode,
            message,
            details: error?.details,
        });
        send(
            res,
            jsonResponse(statusCode, {
                error: "request_failed",
                message,
            }),
            origin,
        );
    }
});

server.listen(config.port, config.host, async () => {
    await loadDb();
    console.log("[license-server] listening", {
        host: config.host,
        port: config.port,
        dataPath: config.dataPath,
        maxDevicesPerLicense: config.maxDevicesPerLicense,
        priceId: config.stripePriceId,
    });
});
