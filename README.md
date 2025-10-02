# WhereAmI: Send GPS location from iOS to macOS

This is 100% vibe-coded universal Swift app that works on macOS and iOS.
It allows iOS to share its GPS location to Macbook, assuming that these
two devices are within the Bluetooth range.
The iOS in this setup acts as the BLE perhipheral.
Mac is requesting the GPS, and upon an approval on iOS, the user should receive the GPS coordinate back.

The purpose is to allow the Macbook to be offline (perhaps during vacation),
but be able to get the physical location for notes, field note etc.

# macOS 

![macOS whereami](docs/whereami_mac.png)

# iOS

![iOS whereami](docs/whereami_ios.jpeg)
