# RoomMate

A shared-expense app for people who live together. Add expenses, split them, see who owes whom, settle up via UPI, chat, plan chores and more.

- **Frontend:** Flutter (Dart 3, Material 3) for Android
- **Backend:** Firebase — Authentication, Cloud Firestore, Cloud Messaging (push), Cloud Functions (Node 20)
- **Languages:** English, Kannada, Hindi · **Themes:** light / dark / system

---

## 1. How it works (user workflow)

```
Open app
  └─ (App Lock enabled?) → fingerprint / PIN screen
       └─ Not signed in → Login / Register
            └─ Signed in, no room → Create / Join Room
                 ├─ Create room  → you become Owner, get a room code + QR
                 └─ Join room    → type code · scan QR · upload QR photo
                                     └─ Pending Approval → Owner approves → Home
            └─ In a room → Home (5 tabs)
```

**Joining a room:** the joiner sends a request → the Owner gets a push notification → Owner approves or rejects in Members → the joiner enters the room automatically.

**Day to day:**
1. Anyone adds an expense (amount, category, paid by, split between, bill photo, optional OCR scan).
2. Balances update live for every member (Firestore streams).
3. "Who owes whom" shows the minimum payments; tap **Pay via UPI** to open GPay / PhonePe, then record the settlement.
4. Everyone gets notifications (in-app + push) for new expenses, announcements, join requests, budget alerts and chat.
5. Monthly: recurring expenses (rent, wifi) are added automatically; reports can be exported as PDF / Excel.

---

## 2. Frontend structure (`lib/`)

| File / folder | Purpose |
|---|---|
| `main.dart` | Starts Firebase, loads theme/language/app-lock, listens to auth, `AuthGate` picks the screen from `appState.status` |
| `app_state.dart` | **Central brain** (`appState`). Auth session, room, members, expenses, bills, settlements, announcements, notifications, join requests. All writes to Firestore go through here |
| `extras.dart` | `extras` service: chores, shopping list, recurring expenses, expense comments, group chat (+unread count), monthly budget, UPI helpers |
| `models.dart` | Data classes (Member, Expense, Category, Announcement …) and formatters (`rupee`, `fmtDate`) |
| `theme.dart` | Colors (`AppColors.of(context)`), `buildTheme(dark:)`, `themeController` |
| `l10n.dart`, `l10n_strings.dart` | Language controller + Kannada/Hindi translation maps. Our own `Text` widget translates automatically |
| `widgets.dart` | Shared widgets: `Text`, `AppCard`, `PrimaryButton`, `Avatar`, `SegmentToggle`, `EmptyState`, `guard()` (shows errors) |

### Screens (`lib/screens/`)

| Group | Screens |
|---|---|
| Auth & room | `login_screen`, `create_join_room_screen`, `pending_approval_screen`, `qr_scan_screen` (scan, show, download, share, upload QR) |
| Main tabs (`home_shell`) | **Home** `home_dashboard` · **Expenses** `expenses_screen` · **Chat** `chat_screen` · **Balance** `who_owes_whom_screen` · **More** `profile_screen` |
| Expenses | `add_expense_screen` (with bill scan), `expense_details_screen` (comments, edit, delete) |
| Room | `members_screen`, `announcements_screen`, `notifications_screen` |
| Money | `payment_history_screen`, `monthly_report_screen`, `recurring_screen` (monthly expenses + budget), `export_screen` |
| Other | `chores_screen` (chores + shopping), `edit_profile_screen` (photo, UPI id) |

### Services (`lib/services/`)

| File | Purpose |
|---|---|
| `auth_service.dart` | Firebase Auth: register, login, logout |
| `push_service.dart` | Asks notification permission, saves the FCM token on the user |
| `export_service.dart` | Builds PDF and Excel reports and shares them |
| `bill_scanner.dart` | ML Kit text recognition → reads amount/title from a bill photo |
| `app_lock.dart` | Biometric/device lock (`local_auth`) shown through `LockGate` |

**State pattern:** `appState`, `extras`, `themeController`, `language`, `appLock` are global `ChangeNotifier`s. Screens use `ListenableBuilder` and rebuild when data changes.

---

## 3. Backend structure

### Firebase services
- **Authentication** — email + password
- **Cloud Firestore** — all data, real-time streams
- **Cloud Messaging** — push notifications
- **Cloud Functions** (`functions/index.js`, region `asia-south1`, needs Blaze plan)

### Firestore data layout

```
users/{uid}                 name, email, roomId, photo, pending*, notifSeenAt, fcmTokens[]
roomCodes/{CODE}            → roomId  (lookup when joining)
rooms/{roomId}              name, code, ownerId, memberIds[], monthlyBudget
  ├─ members/{id}           name, color, photo, upi
  ├─ expenses/{id}          title, amount, category, paidBy, splitBetween, date, billUrl
  │    └─ comments/{id}
  ├─ bills/{id}
  ├─ settlements/{id}       payments between members
  ├─ announcements/{id}
  ├─ notifications/{id}     in-app notification feed
  ├─ joinRequests/{uid}     pending / approved / rejected
  ├─ removedMembers/{uid}
  ├─ chores/{id}
  ├─ shopping/{id}
  ├─ recurring/{id}         monthly expenses
  └─ messages/{id}          group chat
```

### Security rules (`firestore.rules`)
Helpers: `signedIn`, `isMember`, `isRoomOwner`. Rule of thumb: only room members can read/write inside their room; only the owner can approve members, remove members and change settings; users can only edit their own profile.

### Cloud Functions (`functions/index.js`)

| Function | Trigger | Does |
|---|---|---|
| `onRoomNotification` | new doc in `rooms/{id}/notifications` | push to all room members |
| `onJoinRequest` | new doc in `joinRequests` | push to the room owner |
| `onJoinRequestAnswered` | join request updated | push to the requester (approved / rejected) |
| `onChatMessage` | new doc in `messages` | push to everyone except the sender |

### Data flow example (add expense)
```
AddExpenseScreen → appState.addExpense()
  → Firestore: rooms/{id}/expenses (+ notification doc, + budget check)
  → all members' streams update the UI instantly
  → Cloud Function onRoomNotification → FCM push to roommates' phones
```

---

## 4. Packages

`firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`, `image_picker`, `url_launcher` (UPI), `shared_preferences`, `pdf`, `excel`, `path_provider`, `share_plus`, `local_auth`, `google_mlkit_text_recognition`, `mobile_scanner`, `qr_flutter`, `gal`; dev: `flutter_launcher_icons`.

---

## 5. Setup and run

1. Install Flutter + Android Studio.
2. `flutter pub get`
3. Firebase: create a project, enable **Email/Password** auth and **Firestore**, run `flutterfire configure` (creates `lib/firebase_options.dart`).
4. Deploy rules and functions:
   ```
   firebase deploy --only firestore:rules
   cd functions && npm install && cd ..
   firebase deploy --only functions
   ```
5. Run: `flutter run`

## 6. Build a release APK

1. Create a keystore with `keytool`, put its details in `android/key.properties`.
2. Keep `proguard-rules.pro` (ML Kit `-dontwarn` lines) and `minSdk 24`.
3. `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`

**Never commit** `android/key.properties`, `*.jks`, `*.keystore`, `functions/node_modules`.

## 7. Android notes
`android_files/` holds the `AndroidManifest.xml` (permissions: INTERNET, POST_NOTIFICATIONS, USE_BIOMETRIC, CAMERA; UPI `queries`) and `MainActivity.kt` (`FlutterFragmentActivity`, required by app lock).

## 8. Guides in this repo
`STEP9_FEATURES.md`, `STEP10_ICON_SPLASH_DARK.md`, `STEP12_CHAT_EXPORT.md`, `STEP13_ALL_IN_ONE.md`, `STEP14_QR.md`, `PUSH_AND_RELEASE.md` — step-by-step setup notes for each feature batch.
