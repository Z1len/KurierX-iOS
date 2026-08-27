# KurierX iOS — first cloud build

This repository is configured for a free Codemagic iOS Simulator compile check.

1. Upload this folder to a GitHub repository.
2. Add the repository in Codemagic.
3. Start workflow `ios-simulator`.
4. The first build resolves Firebase Swift packages and compiles the SwiftUI/SwiftData project.

## Firebase runtime
Before running on a physical iPhone, register an Apple app in the SAME Firebase project with Bundle ID:
`cz.courierledger.ios`
Download `GoogleService-Info.plist` and add it to `KurierX/` (target KurierX).

## Firestore rule change required for iPhone activation
The current Android rules only accept platform == ANDROID. Change that condition to accept both ANDROID and IOS before testing iPhone activation.

This project is the iOS port foundation. It contains Firebase activation/OWNER flow, local SwiftData models, Vision OCR service, main navigation, goal widget, calendar/customer/salary surfaces and cloud build config. Android-only implementation details (Room, WorkManager, ML Kit, Android intents) must be represented with their iOS equivalents as each feature is completed.
