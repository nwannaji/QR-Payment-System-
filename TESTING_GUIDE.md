# QR Payment System — Complete Testing Guide

## Prerequisites

Before testing, ensure:
1. **Backend is running** at `http://172.16.2.90:3000/api/v1` (or update `lib/config/app_config.dart` line 15)
2. **Flutter is set up**: `flutter doctor` passes
3. **Dependencies installed**: `flutter pub get`
4. **Two test accounts**: One buyer, one merchant (register via app or API)
5. **A merchant QR code**: Either generate one in the merchant flow or create one via API

---

## Phase 1: Authentication

### Test 1.1 — Register a Buyer Account
1. Launch the app → you should see the Login screen
2. Tap **"Sign Up"** at the bottom
3. **Role Selection**: Tap the **"Pay Merchants"** card (buyer role)
4. Fill in:
   - Full Name: `Test Buyer`
   - Email: `buyer@test.com`
   - Phone Number: `08012345678`
   - Password: `test1234` (min 8 chars)
   - Confirm Password: `test1234`
5. **Check** the "I agree to Terms & Conditions" checkbox
6. Tap **"Create Account"**
7. ✅ **Expected**: Loading spinner → redirect to **Buyer Home Screen** with "Hello, Test Buyer" greeting
8. ❌ **Error cases to test**:
   - Uncheck terms → tap Create → SnackBar: "Please agree to terms and conditions"
   - Mismatched passwords → SnackBar about password mismatch
   - Already registered email → error message from server

### Test 1.2 — Register a Merchant Account
1. Log out (Profile → Sign Out)
2. Tap **"Sign Up"**
3. Tap **"Receive Payments"** card (merchant role)
4. Fill in:
   - Full Name: `Test Merchant`
   - Email: `merchant@test.com`
   - Phone Number: `08098765432`
   - Business Name: `Test Business`
   - Business Address: `123 Test Street`
   - Password: `test1234`
   - Confirm Password: `test1234`
5. Check terms → tap **"Create Account"**
6. ✅ **Expected**: Redirect to **Merchant Home Screen** with "Welcome back, Test Business"

### Test 1.3 — Login
1. Log out from any screen
2. Enter email + password
3. Tap **"Sign In"**
4. ✅ **Expected**: Correct home screen for the role (buyer or merchant)
5. ❌ **Test wrong password**: Should show error in red box
6. ❌ **Test empty fields**: Validation messages should appear

### Test 1.4 — Forgot Password
1. From Login screen, tap **"Forgot Password?"**
2. Enter email → tap **"Send Reset Link"**
3. ✅ **Expected**: Screen changes to "Check Your Email" with the email displayed
4. Tap **"Back to Login"**

### Test 1.5 — Password Reset (forced)
1. If backend returns 403 with `requiresPasswordReset: true`, app should redirect to Password Reset screen
2. Enter new password (min 8 chars) + confirm
3. Tap **"Reset Password"**
4. ✅ **Expected**: Redirect to home screen

### Test 1.6 — Token Refresh (P0-1)
1. Login successfully
2. Wait for the access token to expire (or simulate by modifying token in secure storage)
3. Navigate to any screen that makes an API call (e.g., Wallet)
4. ✅ **Expected**: AuthInterceptor should silently refresh the token and replay the request — user should NOT be logged out
5. If refresh also fails, user should be logged out automatically (forceLogout)

---

## Phase 2: Buyer Flow

### Test 2.1 — Buyer Home Screen
1. Login as buyer
2. ✅ **Check**: Shows "Hello, {name}" greeting
3. ✅ **Check**: Balance card displays current wallet balance (or ₦0.00 for new account)
4. ✅ **Check**: Quick actions row — "Scan QR", "History", "Help"
5. ✅ **Check**: Recent transactions section (empty if new account)
6. ✅ **Check**: Notification bell icon (top-right, no action yet)

### Test 2.2 — Wallet Top-Up (Testing)
1. Switch to **Wallet tab** (tab 2)
2. Tap **"Top Up Wallet"** button → bottom sheet appears
3. ✅ **Check**: Shows preset amounts: ₦500, ₦1000, ₦2000, ₦5000, ₦10000
4. Tap **₦1000** choice chip
5. ✅ **Expected**: Loading → success → balance updates to ₦1,000.00
6. **Alternative**: Use "Testing Only" section — tap ₦500/₦1000/₦5000/₦10000 buttons for instant manual funding

### Test 2.3 — SWR Cache (P0-4)
1. After wallet loads, note the balance displayed
2. Navigate away (e.g., to History tab) then back to Home
3. ✅ **Expected**: Balance appears **instantly** from cache (<50ms) — no loading spinner
4. Pull down to refresh → balance refreshes from server
5. Turn off Wi-Fi → navigate to Wallet tab
6. ✅ **Expected**: Balance still shows from cache — no error state if cache exists
7. Turn Wi-Fi back on → balance refreshes in background

### Test 2.4 — Scan QR Code (P0-2 Local Parse)
1. From Buyer Home, tap **"Scan QR"** quick action or bottom icon
2. ✅ **Check**: Camera opens with QR scanner overlay
3. ✅ **Check**: Flash/torch toggle button works in top-right
4. **Test with a valid merchant QR code**:
   - ✅ **Expected**: App **immediately** navigates to Payment Confirmation screen (<50ms) — no loading spinner
   - Background verification happens silently
   - If server returns different merchant info, a SnackBar warning appears
5. **Test with an expired QR code**:
   - ✅ **Expected**: Error dialog "This QR code has expired. Please ask the merchant to generate a new one."
6. **Test with an invalid QR code**:
   - ✅ **Expected**: Falls back to server verification → error dialog if invalid
7. **Test with a Paystack URL QR**:
   - ✅ **Expected**: Opens browser directly (no server call)

### Test 2.5 — Paystack Bank Charge Payment
1. From scanner, scan a valid merchant QR code
2. On Payment Confirmation Screen:
   - ✅ **Check**: Merchant name and first letter avatar display correctly
   - Enter amount in the amount field (e.g., `500`)
   - ✅ **Check**: Amount field only allows numbers and 2 decimal places
3. **Banks dropdown**:
   - ✅ **Check**: Banks load from API (or from cache if previously loaded — P2-3)
   - ✅ **First visit**: Shows "Loading banks..." spinner
   - ✅ **Subsequent visits**: Banks load instantly from 24-hour cache
   - Select a bank from dropdown
4. Tap **"Continue to Payment"**
5. ✅ **Expected**: Browser opens with bank login page
6. **Processing dialog** appears:
   - ✅ **Check**: Shows amount + merchant name
   - ✅ **Check**: 3 steps displayed
   - Tap **"I've Completed Payment"** after completing in browser
7. **Verification**:
   - ✅ **Success**: Shows success dialog with amount + "Paid to {merchant name}"
   - ❌ **Abandoned**: Shows retry dialog with "Re-open Page" and "Try Again"
   - ❌ **Failed**: Shows retry dialog with "Go Back" and "Try Again"
   - ❌ **Processing**: Shows "Check Again" button

### Test 2.6 — In-App PIN Payment (PaymentScreen)
**Note**: PaymentScreen is currently NOT reachable from the main navigation. To test it, you need to either:
- Temporarily add a route in `main.dart`, OR
- Use it via a direct `MaterialPageRoute` in code

If accessible:
1. Enter merchant ID and name (from QR scan data)
2. ✅ **Check**: Merchant info card shows "Paying to {merchant name}"
3. ✅ **Check**: Available balance displays correctly
4. Enter amount → tap Quick Amount chip (e.g., ₦500)
5. Add optional description
6. Tap **"Pay Now"**
7. ✅ **PIN dialog** appears with 4-digit masked input
8. Enter 4-digit PIN → tap **"Confirm"**
9. **Optimistic Payment (P0-3)**:
   - ✅ **Expected**: Success dialog appears **immediately** (<100ms) — balance deducted locally
   - Background: Server processes the payment
   - ✅ **On server success**: Balance refreshes from server (reconciles)
   - ❌ **On server failure**: Success dialog dismissed, error SnackBar shown, balance reversed
   - ❌ **On network error**: "Network error. Please try again." SnackBar, balance reversed

### Test 2.7 — Buyer Transactions
1. Switch to **History tab** (tab 1)
2. ✅ **Check**: Lists wallet ledger entries (topups, payments, refunds)
3. ✅ **Check**: Each entry shows icon, type, date, amount with +/- prefix
4. ✅ **Check**: Pull to refresh works
5. ✅ **Check**: If empty, shows "No transactions yet" with icon

### Test 2.8 — Buyer Profile
1. Switch to **Profile tab** (tab 3)
2. ✅ **Check**: Avatar (or initial letter), name, email displayed
3. Tap **"Edit Profile"** → Edit Profile Screen
4. Tap **"Change PIN"** → Change PIN Screen
5. Tap **"Notifications"** → Notifications Screen
6. Tap **"Sign Out"** → Confirm logout → Login screen

---

## Phase 3: Merchant Flow

### Test 3.1 — Merchant Dashboard
1. Login as merchant
2. ✅ **Check**: "Welcome back, {business name}" greeting
3. ✅ **Check**: Total Balance card shows wallet balance
4. ✅ **Check**: Total Transactions count
5. ✅ **Check**: Today's transactions section (empty or list)
6. ✅ **Check**: Quick actions — "Show QR", "History", "Bank Account"
7. **Pull to refresh**: ✅ Stats and wallet should refresh

### Test 3.2 — QR Code Generation (P0-4 Cached)
1. Switch to **QR Code tab** (tab 1)
2. ✅ **First visit**: Shows loading spinner → QR code appears
3. ✅ **Subsequent visits**: QR code appears **instantly** from cache (if within 5-minute TTL)
4. ✅ **Check**: QR image renders at 250x250 pixels
5. ✅ **Check**: "Scan to pay" label below QR code
6. Tap **"Refresh QR Code"** → new QR generates
7. Tap **"Share QR Code"** → SnackBar: "Share feature coming soon"

### Test 3.3 — Merchant Transaction History
1. Switch to **History tab** (tab 2)
2. ✅ **Check**: Lists received payments with status icons
3. ✅ **Check**: Completed payments show green arrow, pending show amber hourglass
4. ✅ **Check**: Pagination loads more on scroll (if >20 transactions)

### Test 3.4 — Background Sync (P2-2)
**Note**: BackgroundSyncService is defined but not started in the current app. To test:
1. Start the service in merchant/buyer home screen's `initState`
2. Keep the app open on merchant dashboard
3. ✅ **Expected**: Every 30 seconds, wallet balance and stats refresh automatically
4. Make a payment from a buyer account targeting this merchant
5. ✅ **Expected**: Within 30 seconds, the new transaction appears on the dashboard

---

## Phase 4: Profile Management

### Test 4.1 — Edit Profile
1. Navigate to Edit Profile screen
2. ✅ **Check**: All fields pre-populated from current user data
3. Change name, phone
4. **For merchants**: Change business name, business address
5. Tap **"Save Changes"**
6. ✅ **Expected**: Loading → success → navigates back → profile updated

### Test 4.2 — Change PIN
1. Navigate to Change PIN screen
2. **First-time setup**:
   - ✅ **Check**: Shows "Set Your PIN" title
   - Enter new 4-digit PIN
   - Confirm PIN
   - Tap "Set PIN"
   - ✅ **Expected**: Success, navigates back
3. **Subsequent visits**:
   - ✅ **Check**: Shows "Change Your PIN" title
   - Enter current PIN (4 digits)
   - Enter new PIN (4 digits)
   - Confirm new PIN
   - Tap "Change PIN"
   - ✅ **Expected**: Success
4. **Error cases**:
   - Wrong current PIN → error message
   - Mismatched new/confirm PINs → "PINs do not match"

### Test 4.3 — Notifications Settings
1. Navigate to Notifications screen
2. ✅ **Check**: Two toggles — "Money In" and "Money Out"
3. Toggle "Money In" ON
4. ✅ **Expected**: 500ms debounce → API call saves (spinner in app bar)
5. Toggle "Money Out" OFF
6. ✅ **Check**: Phone number displayed in info card

### Test 4.4 — Bank Account (Merchant)
1. Navigate to Bank Account screen
2. **Adding new account**:
   - Select bank from dropdown (Access Bank, GTBank, etc.)
   - Enter 10-digit account number
   - Enter account name (min 3 chars)
   - Tap "Save Bank Account"
   - ✅ **Expected**: Success SnackBar
3. **Updating account**:
   - Change any field
   - Tap "Update Bank Account"
   - ✅ **Expected**: Success
4. **Deleting account**:
   - Tap delete icon in app bar
   - Confirm in dialog
   - ✅ **Expected**: Account removed, form cleared

### Test 4.5 — Avatar Upload
1. In Edit Profile screen, tap the camera icon on the avatar
2. ✅ **Check**: Bottom sheet with "Take Photo" and "Choose from Gallery"
3. Select an image
4. ✅ **Expected**: Avatar updates with new image, spinner shows during upload

---

## Phase 5: Optimization Features

### Test 5.1 — Optimistic Payment (P0-3)
1. As buyer, scan merchant QR code
2. Enter amount and complete payment
3. ✅ **Key test**: The success dialog should appear **before** the server responds
4. ✅ **Success case**: Dialog shows immediately, balance deducts instantly, server confirms within seconds
5. **Simulate failure**: Test with insufficient balance or wrong PIN
   - ✅ **Expected**: Success dialog briefly appears, then is dismissed, error SnackBar shows, balance is reversed
6. **Simulate network failure**: Turn off Wi-Fi during payment
   - ✅ **Expected**: Success dialog appears (optimistic), then network error SnackBar, balance reversed

### Test 5.2 — Stale-While-Revalidate Cache (P0-4)
1. Login and load all screens once (to populate cache)
2. Kill the app completely (not just minimize)
3. Reopen the app
4. ✅ **Expected**: Home screen shows cached data **instantly** — no loading spinners
5. After ~1-2 seconds, data refreshes from server (you may see a brief flash of updated data)
6. **Test offline**: Turn off Wi-Fi, kill app, reopen
7. ✅ **Expected**: All cached data displays from Hive cache, no error state
8. **Test cache expiry**: Wait >30 seconds, pull to refresh on wallet
9. ✅ **Expected**: Fresh data loads, balance updates

### Test 5.3 — Request Deduplication (P1-2)
1. Open the app and navigate to Wallet tab
2. Quickly switch between tabs (Home → History → Wallet → Home)
3. ✅ **Expected**: Only ONE API call per endpoint, not multiple — check network logs in debug console
4. ✅ **No duplicate requests** should appear in the Dio log interceptor

### Test 5.4 — Smart Pre-Fetching (P1-3)
1. Logout completely
2. Login as buyer
3. ✅ **Expected**: After login, wallet, profile, and stats are pre-fetched in background
4. Navigate to any tab — data should appear **instantly** from pre-fetch cache
5. **Without pre-fetch** (previous behavior): Each tab would show loading spinner

### Test 5.5 — Offline Payment Queue (P1-1)
1. Login as buyer with wallet balance
2. **Turn off Wi-Fi/mobile data**
3. Attempt a payment
4. ✅ **Expected**: Optimistic payment still shows success locally
5. When payment API call fails:
   - ✅ **For top-ups**: Should be queued in `OfflineQueueService` and auto-retried when connectivity returns (max 3 attempts)
   - ✅ **For payments**: Local deduction is reversed, error shown, and the payment is enqueued with its idempotency key for safe manual retry
6. **Turn Wi-Fi back on**
7. ✅ **Expected**: Queued top-ups should auto-retry within seconds (triggered by `connectivity_plus` listener)
8. ✅ **Failed payment**: Should show "Retry" button for manual confirmation — NOT auto-retried to avoid confusing UX where a reversed balance suddenly drops again

### Test 5.5a — Idempotency Keys (End-to-End)
This test verifies that idempotency keys prevent double-charges on payment retries.

1. Login as buyer with sufficient wallet balance
2. Start a payment to a merchant
3. ✅ **Check network request**: The POST body should include an `idempotency_key` field (UUID v4 format)
4. ✅ **Check offline queue**: If the payment fails due to network error, the queued operation should have the same `idempotency_key` as the original request
5. **Simulate timeout scenario**:
   - Use a proxy tool (e.g., Charles Proxy, mitmproxy) to delay the server response
   - Or: Complete the payment successfully on the server side, then trigger a retry from the offline queue
   - ✅ **Expected**: The server should return `{ success: true, duplicate: true }` with the original transaction — no second charge is created
6. **Verify no duplicate charge**:
   - Check buyer wallet balance after retry — it should reflect only ONE deduction
   - Check merchant transaction list — there should be only ONE transaction for this payment
7. **Manual retry from offline queue**:
   - When retrying a queued payment, ✅ the `idempotency_key` from the queued operation is sent to the backend
   - ✅ If the original payment was already processed, the server returns the existing transaction instead of creating a duplicate

### Test 5.6 — Banks List Caching (P2-3)
1. As buyer, scan a merchant QR code → reach Payment Confirmation screen
2. ✅ **First visit**: Banks dropdown shows "Loading banks..." spinner, then populates
3. Navigate away and come back
4. ✅ **Second visit**: Banks dropdown shows **instantly** from 24-hour cache — no spinner
5. Kill app, reopen, navigate to payment confirmation
6. ✅ **Expected**: Banks still load from cache (survives app restart)

### Test 5.7 — PIN Hashing (P2-1)
1. Open browser dev tools or network inspector
2. Make a payment or verify PIN
3. ✅ **Check the network request**: Should include BOTH `pin` (plaintext fallback) AND `pin_hash` (SHA-256 of `pin:userId`)
4. The `pin_hash` field should be a 64-character hex string
5. ✅ **Backward compatible**: Backend that doesn't understand `pin_hash` still reads `pin`

### Test 5.8 — HTTPS Enforcement (P2-4)
1. Build the app in **release mode**: `flutter build apk --release`
2. ✅ **Expected**: `android:usesCleartextTraffic="false"` in the release build
3. Any HTTP (non-HTTPS) requests should fail in release builds
4. ✅ **Debug mode**: Cleartext traffic is still allowed for development

---

## Phase 6: Edge Cases and Error Handling

### Test 6.1 — Network Errors
1. Turn off Wi-Fi and mobile data
2. Try every action:
   - Login → ✅ Shows error
   - Load wallet → ✅ Shows cached data if available, error if not
   - Scan QR → ✅ Falls back to server verification, shows error
   - Make payment → ✅ Optimistic shows success, then reverses on error
   - Top up → ✅ Queued offline if enabled
3. Turn connectivity back on
4. ✅ **Expected**: App recovers gracefully, cached data still visible
5. ✅ **Connectivity auto-retry**: Queued top-ups/funds should automatically process when connectivity is restored (via `connectivity_plus` listener in `OfflineQueueService`)

### Test 6.2 — Token Expiry
1. Login successfully
2. Manually delete `auth_token` from secure storage (or wait for natural expiry)
3. Make any API call (e.g., navigate to Wallet)
4. ✅ **Expected**: AuthInterceptor attempts token refresh using `refresh_token`
5. If refresh succeeds → ✅ Request replays, user stays logged in
6. If refresh fails → ✅ User logged out, redirected to login

### Test 6.3 — 403 Password Reset Required
1. If backend returns 403 with `requiresPasswordReset: true` on login
2. ✅ **Expected**: App redirects to Password Reset screen with the userId
3. Complete password reset → ✅ Redirected to home screen

### Test 6.4 — Pull-to-Refresh
1. On any list screen (transactions, history)
2. Pull down to trigger refresh indicator
3. ✅ **Expected**: Data reloads from server, list updates

### Test 6.5 — App Lifecycle (Resume)
1. Open merchant dashboard
2. Switch to another app or browser (for Paystack payment)
3. Return to QR Pay app
4. ✅ **Expected**: Dashboard auto-refreshes with latest data (via `didChangeAppLifecycleState(resumed)`)

### Test 6.6 — Invalid QR Codes
| QR Content | Expected Behavior |
|---|---|
| Empty string | Error: "Empty QR code" |
| Random text (not JSON, not base64) | Falls back to server verify → error "Unrecognized QR code format" |
| Expired QR (past expiry date) | Error: "This QR code has expired" |
| Paystack checkout URL | Opens in external browser |
| Valid compact QR | Navigates to payment screen instantly |
| Valid JSON QR | Navigates to payment screen instantly |

---

## Phase 7: Performance Validation

### Test 7.1 — Perceived Payment Latency
1. Start a timer when scanning QR code
2. Note when payment confirmation appears
3. **Before optimization**: 3-8 seconds expected
4. **After optimization (target)**: <500ms perceived latency
5. ✅ **Key metric**: Time from QR scan to payment screen = <50ms (local parse)
6. ✅ **Key metric**: Time from "Pay Now" tap to success dialog = <100ms (optimistic)

### Test 7.2 — Screen Transition Speed
1. Navigate between tabs rapidly
2. **Before**: Each tab shows 1-3 second loading spinner
3. **After**: ✅ **Cached data appears instantly** (<50ms), background refresh within 1-2s

### Test 7.3 — Banks List Load Time
1. Open Payment Confirmation screen (first time)
2. **Before**: 1-3 seconds loading spinner for banks
3. **After**: ✅ **First load** still shows spinner, but **subsequent visits** load instantly from cache

### Test 7.4 — Duplicate Request Prevention
1. Enable debug logging in `AppConfig`
2. Rapidly switch between Home and History tabs
3. Check console for duplicate `GET /wallet` or `GET /merchant/stats` calls
4. ✅ **Expected**: Only one call per endpoint per second (deduplication active)

---

## Quick Smoke Test Checklist

For rapid regression testing, run through this list after any change:

- [ ] App launches → Login screen appears
- [ ] Buyer login → Home screen with cached balance
- [ ] Merchant login → Dashboard with QR code (from cache)
- [ ] Buyer scan QR → Payment confirmation appears in <100ms
- [ ] Buyer make payment → Success dialog appears in <100ms (optimistic)
- [ ] Buyer top-up → Balance updates immediately
- [ ] Merchant generate QR → QR appears
- [ ] Pull-to-refresh on any screen → Data refreshes
- [ ] Kill and reopen app → Cached data appears instantly
- [ ] Turn off network → Cached data still shows, errors handled gracefully
- [ ] Turn network back on → App recovers, queued top-ups auto-retry, background sync refreshes data
- [ ] Payment retry with idempotency → No duplicate charge, server returns original transaction
- [ ] Profile edit → Changes save successfully
- [ ] PIN change → Success
- [ ] Logout → Clears session, redirects to login