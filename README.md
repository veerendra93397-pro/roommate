# RoomMate (Flutter frontend)

All 10 screens from the design, running on in-memory mock data (no backend yet).

## Run
1. Create a new Flutter project in Android Studio named `roommate` (or run `flutter create roommate`).
2. Copy this `lib/` folder and `pubspec.yaml` over the project's own (replace them).
3. `flutter pub get` then run on an emulator/device. Needs Flutter 3.10+ (Dart 3).

## Structure
- `lib/models.dart`  – data classes + `AppState` (mock data, balance & settle-up logic)
- `lib/theme.dart`, `lib/widgets.dart` – colours, theme, shared widgets
- `lib/screens/` – one file per screen
