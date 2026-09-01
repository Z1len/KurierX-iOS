# KurierX iOS — rebuilt parity build

This project is a native SwiftUI/SwiftData iOS port based on the current Android KurierX main branch and the working Firebase licensing prototype.

Included in this rebuild:
- Android-style 5-tab navigation: Home / Calendar / Statistics / Scanner / More
- KurierX dark/green visual system with compact cards and no oversized top spacer
- Home goal progress, earnings summary, active shift, route cards
- Calendar month grid with shift time + K count
- Statistics period selector and charts
- Vision OCR scanner from Photos with collapsed raw OCR and route creation
- Clients grouped by date and route
- Shifts, salary chart, bonuses/penalties, diesel, advances, goals
- Backup sharing, journal shell, trash restore, advanced mode, settings
- Firebase activation / freeze / revoke listener
- Expanded KurierX Control: key generation/copy/delete, user editing, ACTIVE/FROZEN/BLACKLISTED controls, owner exit
- Keyboard Done toolbar and interactive keyboard dismissal
- Codemagic simulator and unsigned physical-iPhone workflows

Build on Codemagic:
1. Push the project contents to the root of the KurierX-iOS repository.
2. Run `KurierX iOS Simulator Build`.
3. If green, run `KurierX iPhone Unsigned Build`.
4. Download `KurierX-unsigned.ipa` and install through SideStore.

Firebase:
`GoogleService-Info.plist` is already included in `KurierX/Resources`. Firestore rules must allow platform `IOS` in the same places where Android devices are accepted.
