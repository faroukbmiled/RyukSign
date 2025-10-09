# RyukSign

Improved Feather

### Added:
- Background downloading with progress notifications, featuring task queueing and resumable downloads on app refresh (this was a challenge).
- Live Activity support for downloads.  
- Added a collapsible header for downloads (also manages downloads)
- Faster and smoother search with debouncing and background processing, especially for large repositories.
- Tracks previously installed apps and available updates. Clicking an installed app takes you to the Library tab with the app highlighted.
- Auto imports certificates found in app's bundle on first launch (looks in /signing-assets/[folder_name]/ for cert.p12, cert.mobileprovision and cert.txt, where folder_name becomes the certificate display name)
- Added a button for quickly adding popular repositories.
- Added a new “Sources” filter for available updates, (Displays the number of updates)
- Various tweaks to default settings, signing, and more.  

### Todo:
- More UI improvements to the Sources tab.  
- Add a discrete tab for managing downloads
