# KurierX iOS — final single-source project

This package intentionally compiles only one Swift file:

`KurierX/KurierXFinalApp.swift`

The root `project.yml` explicitly points XcodeGen to that file, so old Swift files may remain in the repository without duplicate declarations.

## Upload

1. Keep the existing `KurierX/Resources/GoogleService-Info.plist` in GitHub.
2. Upload `KurierX/KurierXFinalApp.swift` to the same path.
3. Replace root `project.yml` and `codemagic.yaml` with the supplied versions.
4. Commit to `main`.
5. Run `KurierX iOS Simulator Build`.
6. If green, run `KurierX iPhone Unsigned Build` and install the IPA through SideStore.

## Important

- Do not rename `KurierXFinalApp.swift` unless you also change `project.yml`.
- Face ID needs the supplied `project.yml`, because it adds `NSFaceIDUsageDescription`.
- The app first attempts to open the existing SwiftData store. If an old test schema is incompatible, it opens a separate recovery store instead of crashing.
