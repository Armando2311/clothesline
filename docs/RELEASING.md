# Distribution

`Scripts/release-app.sh` builds universal Apple silicon/Intel binaries, signs with Developer ID, submits to Apple's notary service, staples and validates the ticket, then produces `build/Clothesline.zip` and a SHA-256 checksum. It refuses ad hoc identities and missing notary profiles before building. It never publishes a release automatically.

For local distribution, install a **Developer ID Application** identity in your keychain and store credentials with `xcrun notarytool store-credentials clothesline-release`. Set `CODESIGN_IDENTITY` to the identity's full name and `NOTARY_PROFILE=clothesline-release`, then run the script. Never commit certificates or passwords.

The manual GitHub Actions **Signed distribution build** uses repository secrets `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `DEVELOPER_ID_IDENTITY`, `NOTARY_APPLE_ID`, `NOTARY_APP_PASSWORD`, and `APPLE_TEAM_ID`. It imports credentials into a temporary keychain, removes them after the run and delivers an artifact for review. After reviewing the artifact, publish a GitHub Release with a numeric version tag such as `v1.1.0` and attach the ZIP/checksum.

Clothesline's **Check for Updates** action checks the repository's latest published non-prerelease release and opens its verified GitHub release page. Download/install remains explicit; silent replacement and automatic updates are not implemented. Increase `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and keep Xcode `project.yml` settings consistent before publishing. Development branch builds remain ad hoc signed until Developer ID and notary credentials are provided.
