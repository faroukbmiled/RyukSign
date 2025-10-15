# RyukSign

Improved Feather

### Added:
- Background downloading with progress notifications, featuring task queueing and resumable downloads on app refresh (this was a challenge).
- Background repos loading ,importing and installing
- Live Activity support for downloads (download info, progress, paused state...).  
- Added a collapsible downloads header (also manages active downloads)
- Added a floating downloads icon that opens an overlay with more details when clicked — toggle between header and icon in download settings
- Faster and smoother search with debouncing and background processing, especially for large repositories.
- Tracks previously installed apps and available updates. Clicking an installed app takes you to the Library tab with the app highlighted.
- Auto imports certificates found in app's bundle on first launch (looks in /signing-assets/[folder_name]/ for cert.p12, cert.mobileprovision and cert.txt, where folder_name becomes the certificate display name)
- Added a button for quickly adding popular repositories.
- Added an Updates tab to the Sources section (you can toggle in apperance settings between filter or tab)
- Added a new “Sources” filter for available updates, (Displays the number of updates)
- Added appstore links to apps that exists there, both in library tab and sources tab
- Various tweaks to default settings, signing, and more.  

### Todo:
- More UI improvements to the Sources tab.  

## Notes
- Only tested on ios 26
