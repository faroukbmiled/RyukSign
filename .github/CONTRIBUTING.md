# Contributing

RyukSign is a fork of [Feather](https://github.com/claration/Feather), a sideloading app meant to run on stock iOS. To keep compatibility we rely on stock features. The same contribution rules apply, to maintain that integrity.

Any contributions should follow the [Code of Conduct](./CODE_OF_CONDUCT.md).

## Rules

- **No usage of any exploits of any kind.**
- **No contributions related to retrieving any signing certificates owned by companies.**
- **Modifying any hardcoded links should be discussed before changing.**
- **If you're planning on making a large contribution, please [make an issue](https://github.com/faroukbmiled/RyukSign/issues) beforehand.**
- **Your contributions should be licensed appropriately.**
  - RyukSign / Feather: GPLv3
  - AltSourceKit / NimbleKit / Zsign / IDeviceKitten: MIT
  - ElleKit: BSD-3-Clause
- **Typo contributions are okay**, just make sure they are appropriate.
  - This includes localizations.
- **Code cleaning contributions are okay.**

## Building from source

#### Requirements

- Xcode 16.0+ (the project uses synchronized groups, `objectVersion 77`)
- Swift 6.0
- iOS 16.0 deployment target (note: simulator builds may need `IPHONEOS_DEPLOYMENT_TARGET=17.0` due to a SWCompression minimum-target quirk)

1. Clone the repository with submodules:
    ```sh
    git clone https://github.com/faroukbmiled/RyukSign --recursive
    ```
    - `Zsign` and `IDeviceKitten` are submodules — `--recursive` is required.

2. Fetch the local-server SSL pack (used by the on-device install server):
    ```sh
    cd RyukSign && make deps
    ```

3. Open with Xcode:
    ```sh
    open RyukSign.xcworkspace
    ```

#### Signing for development

The committed Xcode project carries the maintainer's signing identity. To build on your own machine, set your own team / enable automatic signing in Xcode's target settings, or use the unsigned CLI path (`make`, which builds with `CODE_SIGNING_ALLOWED=NO`).

#### Localizations

- Localizations live in `RyukSign/Resources/Localizable.xcstrings` (a String Catalog). You need Xcode 15+ or another tool that can edit `.xcstrings`.
- **Do NOT edit the catalog by hand** — use Xcode's String Catalog editor.
- Some localizations were imported from upstream Feather / its V1; if they don't make sense, feel free to correct them.
- After localizing, please have another native speaker review your work. We want high-quality, in-context translations — they will not be merged otherwise (unless you were personally asked to translate).

#### Making a pull request

- Keep contributions in their own branch, not `main`.
- Don't be afraid of reviewers requesting changes — it keeps the project clean and tidy.

## Contributing to Zsign

Zsign is maintained upstream at [claration/Zsign-Package](https://github.com/claration/Zsign-Package/tree/package). Make Zsign changes there.

## Upstream Feather

RyukSign tracks [Feather](https://github.com/claration/Feather) as its upstream. Fixes that aren't RyukSign-specific are welcome upstream too.
