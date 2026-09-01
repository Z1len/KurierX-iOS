# KurierX iOS FULL v5

This project is the iPhone client for KurierX. Android remains in `Z1len/KurierX`; this project belongs in `Z1len/KurierX-iOS`.

## What changed in v5

- iPhone-only target + generated modern launch screen to remove the old letterboxed black bars.
- Custom bottom navigation permanently visible: Главная / Календарь / Статистика / Сканер / Ещё.
- OWNER no longer gets trapped in KurierX Control. OWNER enters the normal KurierX shell and opens Control from `Ещё`.
- User activation is compatible with the currently deployed Android Firestore rules, avoiding the iOS `Missing or insufficient permissions` failure.
- Keyboard dismisses interactively and every form has `Готово` where needed.
- Main dashboard, active shift, plan, closed routes, calendar, statistics, OCR screen, clients, shifts, bonuses/compensations, penalties, fuel/auto expenses, advances, salary reconciliation, goals, backups, audit, trash, developer mode, mileage, settings, tutorial.
- Codemagic package resolution retries transient Google/Firebase 502 failures automatically.

## Build

1. Replace the contents of `Z1len/KurierX-iOS` with this folder and commit to `main`.
2. Codemagic → `KurierX iOS Simulator Build`.
3. If green → `KurierX iPhone Unsigned Build`.
4. Install the resulting `KurierX-unsigned.ipa` through SideStore over the existing app.

## Note about activation compatibility

The deployed Android Firestore rules currently only allow device documents whose `platform` field is `ANDROID` and whose OS field is named `androidVersion`. This iOS build intentionally writes those two compatibility fields while still writing manufacturer `Apple` and the iPhone model. That lets the existing production rules accept iPhone activation without a Firebase-console change.
