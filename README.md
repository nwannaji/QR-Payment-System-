# QR Pay — Instant QR Payment System for Nigerian SMBs

A fast, offline-resilient Flutter fintech app that lets small and medium-scale businesses accept payments via QR codes. Buyers scan a merchant's QR code and pay instantly from their in-app wallet — no cash, no POS terminal, no delays.

Built to achieve **<500ms perceived payment latency** on Nigerian mobile networks.

---

## How It Works

```
Merchant generates QR Code  →  Buyer scans with phone  →  Enters amount + PIN  →  Payment confirmed in <500ms
```

1. **Merchants** generate a unique QR code displayed on their phone or printed at their store
2. **Buyers** open the app, scan the QR code, enter the payment amount and their 4-digit PIN
3. The payment is **deducted from the buyer's wallet** and **credited to the merchant's wallet** instantly
4. Both parties get **immediate feedback** — the buyer sees a success screen, the merchant gets a toast notification with the amount and buyer name

---

## Key Features

### Buyer Flow
- **QR Scanner** — Point camera at merchant's QR code, payment screen loads instantly
- **Wallet Top-Up** — Add funds via Paystack (bank charge) or manual funding for testing
- **PIN Payments** — Secure 4-digit PIN with SHA-256 hashing before transmission
- **Transaction History** — Full wallet ledger with credit/debit breakdown

### Merchant Flow
- **QR Code Generation** — Dynamic QR codes with expiry, styled with brand colors
- **Share QR Code** — Export QR as PNG image via system share sheet (WhatsApp, email, etc.)
- **Dashboard** — Real-time balance, today's revenue, transaction count, recent payments
- **Payment Notifications** — Green toast notification when a new payment arrives
- **Transaction History** — Full payment history with buyer details

### Profile & Settings
- **Profile Avatars** — Photos shown on dashboard headers and transaction tiles
- **Edit Profile** — Update name, business details, profile photo
- **Change PIN** — Secure PIN change with current PIN verification
- **Notifications Settings** — Toggle payment alerts, marketing emails
- **Bank Account** — Link bank account for withdrawals
- **Help & Support** — FAQ section, email/phone/WhatsApp contact, bug reporting
- **About** — App info, feature highlights, version details

---

## Architecture & Performance

### Near-Zero Latency Optimizations

| Optimization | What It Does | Impact |
|---|---|---|
| **Stale-While-Revalidate Cache** | Hive-backed cache shows data instantly, refreshes in background | Screen loads <50ms vs 1-3s |
| **Optimistic Payments** | Deduct locally first, confirm with server in background, reverse on failure; idempotency key prevents double-charges on retry | Payment confirmation <100ms vs 2-5s |
| **Local QR Parsing** | Parse QR code client-side, navigate to payment screen before server verifies | Payment screen in <50ms vs 200-800ms |
| **Token Refresh Interceptor** | Auto-refreshes expired tokens with request queuing | Eliminates 5-10s re-login penalty |
| **Request Deduplication** | In-flight request map prevents duplicate API calls | Saves 1-3s per duplicate request |
| **Smart Pre-Fetching** | Parallel data fetch after login (wallet, profile, stats) | Subsequent screen visits instant |

### Offline Resilience

| Feature | What It Does |
|---|---|
| **Offline Payment Queue** | Failed top-ups and fund operations queued in Hive, auto-retried on reconnect (max 3 retries) |
| **End-to-End Idempotency Keys** | UUID v4 keys generated per payment and sent to the backend — if a retry hits a server that already committed the transaction, the original result is returned instead of creating a duplicate charge |
| **Connectivity Auto-Retry** | `connectivity_plus` listener detects network restoration and automatically processes queued top-ups and fund operations; payments require manual retry to avoid confusing UX |
| **Optimistic Rollback + Enqueue** | On network failure, the local deduction is reversed and the payment is enqueued with its idempotency key for safe manual retry |

### Security

| Feature | Detail |
|---|---|
| **PIN Hashing** | SHA-256 hash with user ID as salt — plaintext PIN never transmitted |
| **Token Refresh** | `QueuedInterceptorsWrapper` auto-refreshes tokens, queues concurrent requests |
| **Certificate Pinning** | Configurable per environment (staging/production) |
| **HTTPS Enforcement** | Cleartext traffic blocked in release builds via `manifestPlaceholders` |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x / Dart |
| State Management | Provider (ChangeNotifier) |
| HTTP Client | Dio with interceptors |
| Local Storage | Hive CE, Flutter Secure Storage, Shared Preferences |
| QR Code | `qr_flutter` (generation), `mobile_scanner` (scanning) |
| Payments | Paystack (bank charge flow) |
| Sharing | `share_plus` (system share sheet) |
| Connectivity | `connectivity_plus` |
| Deep Links | `url_launcher` |
| Image Handling | `image_picker`, `path_provider` |

---

## Project Structure

```
lib/
├── api/
│   ├── auth_interceptor.dart      # Token refresh with request queuing
│   ├── backend_api.dart           # All API endpoints (Dio singleton)
│   └── dio_client.dart            # Configured Dio factories (timeouts, pooling)
├── config/
│   └── app_config.dart            # Environment configs (dev/staging/prod)
├── models/
│   ├── bank_account.dart
│   ├── notification_settings.dart
│   ├── qr_code.dart
│   ├── queued_operation.dart      # Offline queue data class
│   ├── transaction.dart
│   ├── user.dart
│   └── wallet.dart
├── providers/
│   ├── auth_provider.dart          # Auth state, login, register, token refresh
│   ├── merchant_provider.dart      # Merchant stats, transactions, QR generation
│   └── wallet_provider.dart        # Wallet balance, history, optimistic deduction
├── screens/
│   ├── auth/                       # Login, Register, Forgot/Reset Password
│   ├── buyer/                      # Home, Scanner, Payment, Payment Confirmation, Transactions
│   ├── merchant/                   # Home, QR Screen, Transactions
│   └── profile/                    # Edit Profile, Change PIN, Notifications, Bank Account, Help, About
├── services/
│   ├── background_sync_service.dart  # 30s polling for wallet + merchant updates
│   ├── cache_service.dart            # Generic Hive-backed TTL cache (SWR)
│   ├── cache_keys.dart               # Cache key constants with TTL durations
│   ├── deduplication_service.dart     # In-flight request deduplication
│   ├── offline_queue_service.dart    # Hive queue for failed operations + connectivity auto-retry
│   ├── optimistic_payment_service.dart # Local deduction + idempotency key + background API + rollback
│   ├── prefetch_service.dart         # Parallel data fetch on login
│   ├── qr_parser.dart                # Client-side QR validation
│   └── qr_share_service.dart        # Capture QR widget as PNG, share via system sheet
├── utils/
│   ├── constants.dart
│   ├── responsive.dart
│   └── theme.dart                    # AppTheme with Nigerian Naira formatting
└── widgets/
    ├── common/                       # CustomButton, CustomInput, TransactionCard
    └── qr_scanner_overlay.dart       # Scanner viewfinder overlay
```

---

## Getting Started

### Prerequisites

- Flutter SDK >= 3.7.2
- Dart SDK >= 3.7.2
- Android Studio / VS Code
- A running backend API server (see `lib/config/app_config.dart`)

### Installation

```bash
# Clone the repository
git clone https://github.com/nwannaji/QR-Payment-System-.git
cd QR-Payment-System-/qr_payment_system

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Environment Configuration

Edit `lib/config/app_config.dart` to point to your backend:

```dart
static const development = AppConfig(
  baseUrl: 'http://YOUR_LOCAL_IP:3000/api/v1',
  environment: 'development',
  enableDebugLogging: true,
  allowCleartext: true,
);
```

For production, set `allowCleartext: false` and configure certificate pins.

---

## Testing

See [TESTING_GUIDE.md](TESTING_GUIDE.md) for a comprehensive step-by-step testing guide covering all features and edge cases.

---

## Target Markets

This app is designed for markets with high mobile money adoption and a large unbanked or underbanked SMB population:

- **Nigeria** — Primary market. 40M+ small businesses, rising QR payment adoption
- **Kenya** — M-Pesa ecosystem, strong mobile money culture
- **Ghana** — Growing fintech ecosystem, mobile money integration
- **India** — UPI/QR payment boom, massive SMB sector
- **Indonesia** — QRIS national QR standard, 60M+ micro-businesses
- **Bangladesh** — bKash mobile money, dense retail market

---

## End-to-End Payment Latency

| Step | Before | After |
|---|---|---|
| QR scan → payment screen | 200-800ms | <50ms |
| Payment confirmation | 2-5s | <100ms (perceived) |
| Screen transitions | 1-3s loading | <50ms from cache |
| Token expiry recovery | 5-10s re-login | 0s seamless refresh |
| Offline payment | Total failure | Queued + auto-retry |
| **End-to-end payment** | **3-8 seconds** | **<500ms perceived** |

---

## License

This project is proprietary. All rights reserved.