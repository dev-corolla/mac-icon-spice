# Release checklist

The local build is runnable. These steps remain before public distribution:

- Test preview, apply, restore, and update recovery on at least one older supported macOS release; adjust the provisional macOS 14 minimum if needed.
- Test on several signed third-party apps and Mac App Store apps with App Management access. Confirm the apps still launch and their update mechanisms work. Temporary test bundles do not establish this.
- Verify custom colors with macOS Tahoe’s Default, Clear, and Tinted appearance options and record the actual behavior.
- Test the Keychain API key and a live opt-in AI request with your own provider account. Automated tests use mocked responses; model availability and live output quality have not been verified with a paid request.
- Public source repository: https://github.com/dev-corolla/mac-icon-spice. Choose a versioned binary release URL when the distribution checks below are complete.
- Supply a Developer ID certificate and `notarytool` Keychain profile, run `scripts/notarize.sh`, and verify the signed app on another Mac.
- Publish the notarized ZIP and checksums as a GitHub release.
- Create a Homebrew cask using the published version, exact ZIP URL, and SHA-256. Do not publish a cask with placeholder URLs or hashes.

Local building, ad hoc signing, tests, and package validation can be completed without those release credentials.
