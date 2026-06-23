# RyukSign

RyukSign is a fork of [Feather](https://github.com/khcrysalis/Feather) that adds a tweak
manager, on-device file transfer, a reworked download system, and a number of quality-of-life
and reliability improvements. Everything below is on top of what Feather already provides.

## Tweak management

A dedicated Tweaks tab for building a reusable library instead of picking files for every signing
session.

- Import `.dylib` and `.deb` tweaks, give them names, and keep multiple versions of each with one
  marked active.
- Auto-inject rules: inject a tweak into every app you sign, or only into apps whose bundle
  identifier matches a rule you set.
- Per-tweak injection settings: choose the injection path and folder, and pick exactly which app
  extensions a tweak is injected into, listed from the app you are actually signing.
- Auto-injected tweaks are pre-filled in the signing screen and remain fully editable for that
  session, with a badge showing how many are active.
- Tweaks were moved out of the cramped "Modify" menu into their own entry under Advanced.

## File transfer

An optional on-device server for moving IPAs and tweaks onto the device over the local network,
without a cable or a desktop tool.

- Upload from any browser through a drag-and-drop page that also lists and manages files on the
  device.
- Mount the device as a WebDAV drive in Finder or the iOS Files app and copy files in directly.
- Optional password protection for both the web page and the WebDAV mount.
- Uploaded files are routed automatically: IPAs go to the Library, tweaks go to the Tweak Manager.
- A keep-alive option keeps the server reachable while the app is in the background, with a clear
  note about the added battery usage.

## Downloads

- Background downloading with a task queue, resumable downloads across app refreshes, and progress
  notifications.
- Background loading, importing, and installing of repositories.
- Live Activity support showing download details, progress, and paused state.
- A collapsible downloads header that also manages active downloads, plus a floating download
  button that opens a detailed overlay. Switch between the two in download settings.

## Sources and updates

- Faster, smoother search with debouncing and background processing, built for large repositories.
- Tracking of installed apps and available updates; tapping an installed app jumps to the Library
  tab with that app highlighted.
- An Updates view in the Sources section, shown either as a filter or as its own tab depending on
  your preference.
- An update count on the Sources tab.
- App Store links for apps that are available there, in both the Library and Sources tabs.
- A shortcut for quickly adding popular repositories.

## Certificates

- Automatic import of certificates bundled with the app on first launch. RyukSign looks under
  `signing-assets/<folder_name>/` for `cert.p12`, `cert.mobileprovision`, and `cert.txt`, where the
  folder name becomes the certificate's display name.

## Interface and experience

- Animated, swipe-to-dismiss notifications used for confirmations such as imports, copies, and
  signing results, with matching haptics and an option to keep a message on screen until dismissed.
  These replace several blocking pop-ups.
- A configurable tab bar: reorder tabs, hide the ones you do not use, and choose which tab the app
  opens to. Settings always stays reachable.
- Consistent icons across the signing Advanced screen and assorted layout cleanups.

## Reliability and performance

- The Sources tab no longer freezes for a moment when first opened on large repositories; the heavy
  list work now runs off the main thread.
- Loading placeholders no longer appear in the wrong place while a source is loading or empty.
- Shared IPAs open reliably across devices, not only on the device the file was created on.
- File transfers from Windows over WebDAV no longer create a duplicate empty file or import under a
  random name.
- Background audio used to keep work alive is shared correctly, so downloads and file transfer no
  longer cut each other off.

## Notes

- Supports iOS 16 and later.
