# IPA builds

The **iOS IPA** GitHub Actions workflow builds `main` on the `xcode-27` macOS
runner. It also supports **Run workflow** from the Actions page. It runs the full
Swift package tests, archives the existing `Midoku` scheme for a physical iOS
device in Release configuration, and packages the app in `Payload/Midoku.app`.

A successful run uploads `Midoku-unsigned-<commit>` with:

- `Midoku-unsigned.ipa`
- `SHA256SUMS.txt`
- `BUILD.txt`, recording the source commit and Xcode version

Artifacts are retained for seven days. The workflow uses read-only repository
permissions and no signing secrets. It preserves the project bundle identifier,
deployment target, and signing team; signing is disabled only for this build.

**This IPA is unsigned.** It needs a valid Apple signing identity and a matching
provisioning profile before installation. It is not a TestFlight or App Store
export. For an Apple-signed export, archive using the existing automatic signing
configuration on an authorized Mac, then use Xcode Organizer's distribution flow.

The current runner is a public preview with Xcode 27. Its availability and SDK
versions are documented in the [official runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).
Native compilation and test results must be read from each run; creating this
workflow alone is not evidence that the app builds or has passed device checks.
