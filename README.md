# Document Picker for Adobe AIR (iOS)

**Open-source source package for an Adobe AIR Native Extension (ANE) that presents the iOS Files document picker to select `.xlsx` workbooks.**

> **Status: source preview — not device-verified.** The Objective-C implementation and build scripts are provided, but this repository does **not** contain a verified iOS ANE release. Build the native extension with Xcode on macOS and test it on physical devices before production use.

## Features

- Native `UIDocumentPickerViewController` UI for Files, iCloud Drive and enabled third-party file providers.
- One `.xlsx` workbook per request; legacy `.xls` is not supported.
- Maximum import size of **20 MiB** (20 × 1024 × 1024 bytes).
- Copies the selected workbook to an app-owned temporary cache location, without modifying the original.
- File coordination and security-scoped resource access where applicable.
- Async result notifications via Adobe AIR `StatusEvent` (`SELECT`, `CANCEL`, `ERROR`).
- iOS **12.0+** deployment target (configurable) and **arm64 device** architecture; no simulator build.

## Requirements

| Component | Requirement |
| --- | --- |
| Build host | macOS with full Xcode installation and iPhoneOS SDK |
| AIR | Harman/Adobe AIR SDK **51.4.1** used for the original scripts (other versions unverified) |
| Toolchain | Xcode Command Line Tools (`xcrun`), Java compatible with your AIR SDK, `unzip` |
| Test target | Physical iPhone or iPad and ordinary app signing/provisioning |

The build script uses `iPhone-ARM` packaging and targets arm64. The compiled ANE is not included in source control.

## Repository layout

```text
as3/com/fdp/documentpicker/DocumentPickerExtension.as  # Minimal AS3 context entry point
ios/FDPDocumentPicker.m                              # iOS Objective-C implementation
build-macos.sh                                       # Compile and package iOS ANE
build-api.ps1                                        # Windows: compile the AS3 SWC only
extension.xml                                        # AIR extension descriptor
platform-ios.xml                                     # Native framework linkage
examples/BasicUsage.as                              # Event-handling example
```

## Build the iOS ANE (macOS)

1. Install full Xcode and select it with `xcode-select` if necessary.
2. Install an AIR SDK with `bin/acompc`, `bin/adt`, and `include/FlashRuntimeExtensions.h`.
3. From the repository root run:

```bash
bash build-macos.sh /absolute/path/to/AIRSDK_51.4.1
```

Output: `dist/FDPDocumentPicker.ane`. This is a real native build only when the command succeeds on macOS. The script checks its arm64 archive and the packaged ANE.

The default minimum iOS version is 12.0; override it with:

```bash
FDP_MIN_IOS=13.0 bash build-macos.sh /absolute/path/to/AIRSDK_51.4.1
```

### Windows: compile only the ActionScript API

```powershell
./build-api.ps1 -AirSdk 'C:\AIRSDK_51.4.1'
```

This creates `build/FDPDocumentPicker.swc`, **not** an iOS ANE. The Objective-C code cannot be built using this script.

## Integrate into an Adobe AIR app

1. Build `dist/FDPDocumentPicker.ane` on macOS.
2. Add it to your app's ANE library directory and configure your ActionScript compiler/package command to include it.
3. Add the extension ID to the **iOS application descriptor**:

```xml
<extensions>
    <extensionID>com.fdp.DocumentPicker</extensionID>
</extensions>
```

4. Package/sign the iOS app with the same ANE available to the packaging tool.
5. Create the extension context and handle status events, as demonstrated in [`examples/BasicUsage.as`](examples/BasicUsage.as).
6. For `SELECT`, use the returned **local** `file://` URL to read the workbook from AIR; call `releaseSelectedFile` **after the asynchronous read completes**, then dispose the context when finished.

**Important:** The native extension is a picker, not an Excel parser. Your AIR application must implement its own `.xlsx` parsing and workbook validation. No standalone sample AIR application is provided.

## Native API

Extension ID: `com.fdp.DocumentPicker`; context type: `""`.

| `ExtensionContext.call()` method | Return / meaning |
| --- | --- |
| `isSupported` | `Boolean` indicating native context availability |
| `browseExcel` | `Boolean`; `true` means the request was accepted, not that a file was selected |
| `cancel` | Cancel an active picker/request |
| `releaseSelectedFile` | Remove the extension-owned cached copy |

The result is delivered through `StatusEvent.STATUS`:

| `event.code` | `event.level` (JSON) |
| --- | --- |
| `SELECT` | `{"url":"file:///.../workbook.xlsx"}` |
| `CANCEL` | `{}` |
| `ERROR` | `{"code":"read"}` (also `size`, `type`, `presentation`) |

Do not log returned file URLs if filenames or paths are sensitive. Do not call `releaseSelectedFile` before your app finishes loading the file.

## Known limitations and verification

- **Not yet validated on a physical iPhone/iPad**, including iCloud, provider downloads, cancellation, sheet dismissal, and iPad presentation.
- No iOS simulator slice; only `arm64` physical-device builds are supported by the script.
- Accepts `.xlsx` files only and caps native copy size at 20 MiB; it does not validate Excel workbook content.
- The original project included app-specific integration tests referencing private app modules not present in this standalone package; those tests were intentionally excluded rather than advertised as runnable.
- Compatibility with AIR SDKs other than 51.4.1 and newer Xcode/iOS versions is not guaranteed.

**Before release:** compile on macOS, sign a test app and validate local, iCloud and third-party picks; empty/oversized/invalid workbooks; cancel/retry; app backgrounding; delayed provider downloads; context disposal during reads; and cleanup. Check that originals remain unchanged.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Please include AIR SDK, Xcode, iOS version, device model and reproduction steps with bug reports.

## License

**A license has not been selected yet.** Before publishing for community reuse, the repository owner should add a `LICENSE` file (for example MIT or Apache-2.0) after confirming ownership and permission to license all included code. A public GitHub repository alone does not grant reuse rights.

## References

- [Apple Document Picker Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/DocumentPickerProgrammingGuide/AccessingDocuments/AccessingDocuments.html)
- [AIR ANE packaging documentation](https://airsdk.dev/docs/building/air-developer-tool/commands/package)
