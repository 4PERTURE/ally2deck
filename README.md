# Ally2Deck
This script will extract, patch and sign the ROG XBOX ALLY AMD Graphics Driver so that it works on the Steam Deck.
It is highly experimental (and will always be, we are literally patching and installing a driver not designed for our device).
Use it at your own risk.
Tested on Windows 11 Enterprise LTSC, with the 25H2 update manually installed.
This script was built based on the work from [otti83](https://github.com/otti83/apu_driver_test).
It was made to simplify and automate the process so that any user can try this.

# Disclaimer:
I am NOT responsible for any issues caused by using this script.
It is provided as-is, and the user acknowledges and accepts the risks of using it.
This script enables testsigning as it is required for us to use self-signed drivers.
While this is a security risk, just make sure you aren't downloading any sus drivers from shady websites.
If you get a watermark on your desktop, you can remove it with [Universal Watermark Disabler](https://winaero.com/download-universal-watermark-disabler/).


# Dependencies:
The script should download and install all dependencies on its own (7zip, Windows SDK).
However, you do need to manually get the driver from [here](https://rog.asus.com/gaming-handhelds/rog-ally/rog-xbox-ally-2025/helpdesk_download/).

# How to use:
- Download the script
- Download the driver
- Place the driver on on the same folder as the script, and rename it to AMDDriver.exe
- Right click and press "Run with PowerShell"
- Everything else should be handled by the script

# Issues:
Please report any issues you have, as I tested it on my system and it works fine, but that might not be the case for everyone.