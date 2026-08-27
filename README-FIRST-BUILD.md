# KurierX iOS - Firebase build

This project is configured for Firebase project KurierX and bundle ID `cz.courierledger.ios`.
`GoogleService-Info.plist` is already included in `KurierX/Resources`.

## GitHub / Codemagic
Replace the files in your existing `KurierX-iOS` repository with the contents of this folder, commit, then in Codemagic run:

- `KurierX iOS Simulator Build` first. It validates Swift + Firebase compilation.
- `KurierX iPhone Unsigned Build` after the simulator build is green. It produces `KurierX-unsigned.ipa` for later signing/sideloading.

## Firebase rule required for iPhone activation
In Firestore Rules change only the platform check from:
`request.resource.data.platform == 'ANDROID'`
to:
`request.resource.data.platform in ['ANDROID', 'IOS']`
then Publish.

Android and iOS continue to use the same `users`, `devices`, `activation_keys`, `blacklist`, and `audit_log` collections.
