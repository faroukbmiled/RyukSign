# RyukSign

Improved Feather

### Added:
- Background downloading with progress notifications, featuring task queueing and resumable downloads on app refresh (this was a challenge).
- Added a collapsible header for downloads (also manages downloads)
- Faster and smoother search with debouncing and background processing, especially for large repositories.
- Tracks previously installed apps and available updates. Clicking an installed app takes you to the Library tab with the app highlighted.
- Auto imports certificates found in app's ipa archive (looks in /certificates/dist/ and /certificates/dev/ for certificate.p12, certificate.mobileprovision and password.txt)
- Added a button for quickly adding popular repositories.
- Added a new “Sources” filter for available updates, (Displays the number of updates)
- Various tweaks to default settings, signing, and more.  

### Todo:
- Live Activity support for downloads.  
- More UI improvements to the Sources tab.  
- Add a discrete tab for managing downloads
