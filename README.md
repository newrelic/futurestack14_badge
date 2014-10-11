## FutureStack 14 Badge Firmware

This firmware will turn your FutureStack badge into a simple NFC tag reader and screen target.  To get started, register an account with http://electricimp.com, BlinkUp your badge using the Electric Imp [Android](https://play.google.com/store/apps/details?id=com.electricimp.electricimp) or [iOS](https://itunes.apple.com/lb/app/electric-imp/id547133856?mt=8) mobile app, and create a new model using the IDE containing the code in device.nut and agent.nut.  Hit "Build and Run" and your badge should be ready to go.  Additionally, you can use cat.rb to push an image to your badge.

## Other resources
### Electric Imp
To explore more about Electric Imp, check out their dev center [here](https://electricimp.com/docs).  If you want to use your Imp in your own hardware project, check out [this page](https://electricimp.com/docs/gettingstarted/devkits) to find a breakout board.

### E-Paper Screen
The e-paper screen on your badge is made by [Pervasive Displays](http://www.pervasivedisplays.com).  You can find more information on the generation 2 2.7" display [here](http://repaper.org).

### NXP NFC Controller
The NFC chip on the badges is an NXP PN532.  You can find the datasheet [here]( http://www.adafruit.com/datasheets/pn532longds.pdf).  The user manual (a bit higher level) is [here]( http://www.adafruit.com/datasheets/pn532um.pdf) and an application note is [here]( http://www.adafruit.com/datasheets/PN532C106_Application%20Note_v1.2.pdf).  With these datasheets, you'll be able to tailor the NFC chip's behavior to your heart's content.

#### Flash Memory
Details on the flash memory chip on the badges can be found [here](http://www.macronix.com/Lists/Datasheet/Attachments/1610/MX25L8006E,%203V,%208Mb,%20v1.4.pdf).

### Power
Your badge is rechargeable via the micro USB port on the side.  It does not need to be on to charge.

## Contributions
Contributions are more than welcome. Bug reports with specific reproduction
steps are great. If you have a code contribution you'd like to make, open a
pull request with suggested code.

Pull requests should:

 * Clearly state their intent in the title
 * Have a description that explains the need for the changes

By contributing to this project you agree that you are granting New Relic a
non-exclusive, non-revokable, no-cost license to use the code, algorithms,
patents, and ideas in that code in our products if we so choose. You also agree
the code is provided as-is and you provide no warranties as to its fitness or
correctness for any purpose.

## License
Portions of this code used with permission from [Javier Montaner](https://github.com/jmgjmg/eImpNFC).

Copyright (c) 2014 New Relic, Inc. See the LICENSE file for license rights and limitations (MIT).

