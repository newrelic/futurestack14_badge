[![Archived header](https://github.com/newrelic/open-source-office/raw/master/examples/categories/images/Archived.png)](https://github.com/newrelic/open-source-office/blob/master/examples/categories/index.md#archived)

## FutureStack 14 Badge Firmware

This firmware will turn your FutureStack badge into a simple NFC tag reader and screen target.  To get started, register an account with http://electricimp.com, BlinkUp your badge using the Electric Imp [Android](https://play.google.com/store/apps/details?id=com.electricimp.electricimp) or [iOS](https://itunes.apple.com/lb/app/electric-imp/id547133856?mt=8) mobile app, and create a new model using the IDE containing the code in device.nut and agent.nut.  Hit "Build and Run" and your badge should be ready to go.  Additionally, you can use robot.rb to push an image to your badge.  Just make sure to edit it with your agent URL.

## Tips for getting started
* If you're using an Android phone, you may have better luck using the "legacy mode" during the BlinkUp process.
* The main runloop of the device firmware can be found at the very bottom of the file [here](https://github.com/newrelic/futurestack14_badge/blob/master/device.nut#L1814-L1825).
* The device code is a little lengthy due to the number of driver classes.  Use code collapsing to make the file a bit more navigable.
* When blinking the badge up, you'll need to hold your phone over the phototransistor labeled Q1: 
![phototransistor](https://www.evernote.com/shard/s203/sh/13c3f963-e924-422f-8d1d-96544596ed10/a80d69b1926e2dc751f863632668acdf/res/b600769f-ac7c-41df-9290-1ae1359aec00/skitch.png?resizeSmall&width=832)
* Electric Imp has an excellent guide on the BlinkUp process [here](https://electricimp.com/docs/gettingstarted/1-blinkup/).
* The badge's WiFi radio will only work on 2.4GHz networks.
* See this [troubleshooting guide](https://electricimp.com/docs/troubleshooting/blinkup/) if you're having issues getting the badge online.

## Other resources
### Electric Imp
To explore more about Electric Imp, check out their dev center [here](https://electricimp.com/docs).  If you want to use your Imp in your own hardware project, check out [this page](https://electricimp.com/docs/gettingstarted/devkits) to find a breakout board.

### E-Paper Screen
The e-paper screen on your badge is made by [Pervasive Displays](http://www.pervasivedisplays.com).  You can find more information on the generation 2 2.7" display [here](http://repaper.org).

### NXP NFC Controller
The NFC chip on the badges is an NXP PN532.  You can find the datasheet [here]( http://www.adafruit.com/datasheets/pn532longds.pdf).  The user manual (a bit higher level) is [here]( http://www.adafruit.com/datasheets/pn532um.pdf) and an application note is [here]( http://www.adafruit.com/datasheets/PN532C106_Application%20Note_v1.2.pdf).  With these datasheets, you'll be able to tailor the NFC chip's behavior to your heart's content.

### Flash Memory
Details on the flash memory chip on the badges can be found [here](http://www.macronix.com/Lists/Datasheet/Attachments/1610/MX25L8006E,%203V,%208Mb,%20v1.4.pdf).

### IO Expander
Since the Imp is a little short on pins, the badge includes a handy IO expander ([datasheet](http://www.semtech.com/images/datasheet/sx150x_456.pdf)).  The unused pins of the IO expander are broken out on the side of the PCB.  The interrupt line of this chip is connected to pin 1 of the Imp, which can be used for waking interrupts.

### Power
Your badge is rechargeable via the micro USB port on the side.  It does not need to be on to charge.  The 850mAh lithium polymer battery ([datasheet](https://www.sparkfun.com/datasheets/Batteries/063048%20Li-polymer.pdf)) is protected by an over/under charge and short protection circuit ([datasheet](http://dlnmh9ip6v2uc.cloudfront.net/datasheets/Prototyping/BatteryProtection.pdf)).

### Pushing an Image to Your Badge
You can use robot.rb to push an image to your badge. You'll need to edit the AGENT_URL variable with your Electric Imp agent URL.

robot.rb requires that the ImageMagick libraries are installed.
* On Ubuntu: `$ sudo apt-get install libmagickwand-dev`
* On CentOS: `$ yum install ImageMagick-devel`
* On Mac, you can use Homebrew: `$ brew install imagemagick`

To install the gems needed for robot.rb:
```
    $ gem install rmagick
    $ gem install httparty
```    
You can push the robot.png image to your badge with the command: `$ ruby robot.rb`

If you want to use your own image, replace robot.png with your own black and white image. The e-ink screen of the badge is 264 x 176, so your image should fit within those dimensions.

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

