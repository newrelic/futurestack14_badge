/*****************************************\
*        FUTURESTACK 14 BADGE DEMO        *
*           (c) 2014 New Relic            *
*                                         *
* For more information, see:              *
* github.com/newrelic/futurestack14_badge *
\*****************************************/

const SPICLK = 15000;

const CONNECT_TIMEOUT         = 60;    // 60 seconds
const RUNLOOP_INTERVAL        = 3;     // 3 seconds


// Semi-generic SPI Flash Driver
class SpiFlash {
    // Clock up to 86 MHz (we go up to 15 MHz)
    // device commands:
    static WREN     = "\x06"; // write enable
    static WRDI     = "\x04"; // write disable
    static RDID     = "\x9F"; // read identification
    static RDSR     = "\x05"; // read status register
    static READ     = "\x03"; // read data
    static FASTREAD = "\x0B"; // fast read data
    static RDSFDP   = "\x5A"; // read SFDP
    static RES      = "\xAB"; // read electronic ID
    static REMS     = "\x90"; // read electronic mfg & device ID
    static DREAD    = "\x3B"; // double output mode, which we don't use
    static SE       = "\x20"; // sector erase (Any 4kbyte sector set to 0xff)
    static BE       = "\x52"; // block erase (Any 64kbyte sector set to 0xff)
    static CE       = "\x60"; // chip erase (full device set to 0xff)
    static PP       = "\x02"; // page program
    static RDSCUR   = "\x2B"; // read security register
    static WRSCUR   = "\x2F"; // write security register
    static ENSO     = "\xB1"; // enter secured OTP
    static EXSO     = "\xC1"; // exit secured OTP
    static DP       = "\xB9"; // deep power down
    static RDP      = "\xAB"; // release from deep power down
    static PAGESIZE = 256;

    // offsets for the record and playback sectors in memory
    // 64 blocks
    // first 48 blocks: playback memory
    // blocks 49 - 64: recording memory
    static totalBlocks = 64;
    static playbackBlocks = 48;
    static recordOffset = 0x2FFFD0;

    // manufacturer and device ID codes
    mfgID = null;
    devID = null;

    // spi interface
    spi = null;
    cs_l = null;
    
    booted = false;

    // constructor takes in pre-configured spi interface object and chip select GPIO
    constructor(spiBus, csPin) {
        this.spi = spiBus;
        this.cs_l = csPin;

        spi.configure(MSB_FIRST | CLOCK_IDLE_LOW, SPICLK);
        
        wake();  // In case we were sleeping
        
        // read the manufacturer and device ID
        cs_l.write(0);
        spi.write(RDID);
        local data = spi.readblob(3);
        this.mfgID = data[0];
        this.devID = (data[1] << 8) | data[2];
        cs_l.write(1);
        
        if (this.mfgID != 0x00) {
            booted = true;
        }
    }

    function wrenable() {
        cs_l.write(0);
        spi.write(WREN);
        cs_l.write(1);
    }

    function wrdisable() {
        cs_l.write(0);
        spi.write(WRDI);
        cs_l.write(1);
    }

    // pages should be pre-erased before writing
    function write(addr, data) {
        wrenable();

        // check the status register's write enabled bit
        if (!(getStatus() & 0x02)) {
            server.error("Device: Flash Write not Enabled");
            return 1;
        }

        cs_l.write(0);
        // page program command goes first
        spi.write(PP);
        // followed by 24-bit address
        spi.write(format("%c%c%c", (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        spi.write(data);
        cs_l.write(1);

        // wait for the status register to show write complete
        // typical 1.4 ms, max 5 ms
        local timeout = 50000; // time in us
        local start = hardware.micros();
        while (getStatus() & 0x01) {
            if ((hardware.micros() - start) > timeout) {
                server.error("Device: Timed out waiting for write to finish");
                return 1;
            }
        }

        return 0;
    }

    // allow data chunks greater than one flash page to be written in a single op
    function writeChunk(addr, data) {
        // separate the chunk into pages
        data.seek(0,'b');
        for (local i = 0; i < data.len(); i+=PAGESIZE) {
            local leftInBuffer = data.len() - data.tell();
            if ((addr+i % PAGESIZE) + leftInBuffer >= PAGESIZE) {
                // Realign to the end of the page
                local align = PAGESIZE - ((addr+i) % PAGESIZE);
                write((addr+i),data.readblob(align));
                leftInBuffer -= align;
                i += align;
                if (leftInBuffer <= 0) break;
            }
            if (leftInBuffer < PAGESIZE) {
                write((addr+i),data.readblob(leftInBuffer));
            } else {
                write((addr+i),data.readblob(PAGESIZE));
            }
        }
    }

    function read(addr, bytes) {
        cs_l.write(0);
        // to read, send the read command and a 24-bit address
        spi.write(READ);
        spi.write(format("%c%c%c", (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        local readBlob = spi.readblob(bytes);
        cs_l.write(1);
        return readBlob;
    }

    function getStatus() {
        cs_l.write(0);
        spi.write(RDSR);
        local status = spi.readblob(1);
        cs_l.write(1);
        return status[0];
    }

    function sleep() {
        cs_l.write(0);
        spi.write(DP);
        cs_l.write(1);
        spi.configure(CLOCK_IDLE_LOW | MSB_FIRST | CLOCK_2ND_EDGE, SPICLK);
   }

    function wake() {
        spi.configure(MSB_FIRST | CLOCK_IDLE_LOW, SPICLK);
        cs_l.write(0);
        spi.write(RDP);
        cs_l.write(1);
    }

    // erase any 4kbyte sector of flash
    // takes a starting address, 24-bit, MSB-first
    function sectorErase(addr) {
        this.wrenable();
        cs_l.write(0);
        spi.write(SE);
        spi.write(format("%c%c%c", (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        cs_l.write(1);
        // wait for sector erase to complete
        // typ = 60ms, max = 300ms
        local timeout = 300000; // time in us
        local start = hardware.micros();
        while (getStatus() & 0x01) {
            if ((hardware.micros() - start) > timeout) {
                server.error("Device: Timed out waiting for write to finish");
                return 1;
            }
        }
        return 0;
    }

    // set any 64kbyte block of flash to all 0xff
    // takes a starting address, 24-bit, MSB-first
    function blockErase(addr) {
        //server.log(format("Device: erasing 64kbyte SPI Flash block beginning at 0x%06x",addr));
        this.wrenable();
        cs_l.write(0);
        spi.write(BE);
        spi.write(format("%c%c%c", (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        cs_l.write(1);
        // wait for sector erase to complete
        // typ = 700ms, max = 2s
        local timeout = 2000000; // time in us
        local start = hardware.micros();
        while (getStatus() & 0x01) {
            if ((hardware.micros() - start) > timeout) {
                server.error("Device: Timed out waiting for write to finish");
                return 1;
            }
        }
        return 0;
    }

    // clear the full flash to 0xFF
    function chipErase() {
        server.log("Device: Erasing SPI Flash");
        this.wrenable();
        cs_l.write(0);
        spi.write(CE);
        cs_l.write(1);
        // chip erase takes a *while*
        // typ = 25s, max = 50s
        local timeout = 50000000; // time in us
        local start = hardware.micros();
        while (getStatus() & 0x01) {
            if ((hardware.micros() - start) > timeout) {
                server.error("Device: Timed out waiting for write to finish");
                return 1;
            }
        }
        server.log("Device: Done with chip erase");
        return 0;
    }

    // erase the message portion of the SPI flash
    // 2880000 bytes is 45 64-kbyte blocks
    function erasePlayBlocks() {
        server.log("Device: clearing playback flash sectors");
        for(local i = 0; i < this.playbackBlocks; i++) {
            if(this.blockErase(i*65535)) {
                server.error(format("Device: SPI flash failed to erase block %d (addr 0x%06x)",
                    i, i*65535));
                return 1;
            }
        }
        return 0;
    }

    // erase the record buffer portion of the SPI flash
    // this is a 960000-byte sector, beginning at block 46 and going to block 60
    function eraseRecBlocks() {
        server.log("Device: clearing recording flash sectors");
        for (local i = this.playbackBlocks; i < this.totalBlocks; i++) {
            if(this.blockErase(i*65535)) {
                server.error(format("Device: SPI flash failed to erase block %d (addr 0x%06x)",
                    i, i*65535));
                return 1;
            }
        }
        return 0;
    }
}

// IO Expander classes
class SX150x{
    //Private variables
    _i2c       = null;
    _addr      = null;
    _callbacks = null;
 
    //Pass in pre-configured I2C since it may be used by other devices
    constructor(i2c, address = 0x40) {
        _i2c  = i2c;
        _addr = address;  //8-bit address
        _callbacks = [];
    }
 
    function readReg(register) {
        local data = _i2c.read(_addr, format("%c", register), 1);
        if (data == null) {
            server.error("I2C Read Failure. Device: "+_addr+" Register: "+register);
            return -1;
        }
        return data[0];
    }
    
    function writeReg(register, data) {
        _i2c.write(_addr, format("%c%c", register, data));
    }
    
    function writeBit(register, bitn, level) {
        local value = readReg(register);
        value = (level == 0)?(value & ~(1<<bitn)):(value | (1<<bitn));
        writeReg(register, value);
    }
    
    function writeMasked(register, data, mask) {
        local value = readReg(register);
        value = (value & ~mask) | (data & mask);
        writeReg(register, value);
    }
 
    // set or clear a selected GPIO pin, 0-16
    function setPin(gpio, level) {
        writeBit(bank(gpio).REGDATA, gpio % 8, level ? 1 : 0);
    }
 
    // configure specified GPIO pin as input(0) or output(1)
    function setDir(gpio, output) {
        writeBit(bank(gpio).REGDIR, gpio % 8, output ? 0 : 1);
    }
 
    // enable or disable internal pull up resistor for specified GPIO
    function setPullUp(gpio, enable) {
        writeBit(bank(gpio).REGPULLUP, gpio % 8, enable ? 0 : 1);
    }
    
    // enable or disable internal pull down resistor for specified GPIO
    function setPullDown(gpio, enable) {
        writeBit(bank(gpio).REGPULLDN, gpio % 8, enable ? 0 : 1);
    }
 
    // configure whether specified GPIO will trigger an interrupt
    function setIrqMask(gpio, enable) {
        writeBit(bank(gpio).REGINTMASK, gpio % 8, enable ? 0 : 1);
    }
 
    // clear interrupt on specified GPIO
    function clearIrq(gpio) {
        writeBit(bank(gpio).REGINTMASK, gpio % 8, 1);
    }
 
    // get state of specified GPIO
    function getPin(gpio) {
        return ((readReg(bank(gpio).REGDATA) & (1<<(gpio%8))) ? 1 : 0);
    }
 
    //configure which callback should be called for each pin transition
    function setCallback(gpio, callback){
        _callbacks[gpio] = callback;
    }
 
    function callback(){
        //server.log("Checking for callback...");
        local irq = getIrq();
        //server.log(format("IRQ = %08x",irq));
        clearAllIrqs();
        for (local i = 0; i < 16; i++){
            if ( (irq & (1 << i)) && (typeof _callbacks[i] == "function")){
                _callbacks[i]();
            }
        }
    }
}

class SX1506 extends SX150x{
    // I/O Expander internal registers
    static BANK_A = {   REGDATA    = 0x01,
                        REGDIR     = 0x03,
                        REGPULLUP  = 0x05,
                        REGPULLDN  = 0x07,
                        REGINTMASK = 0x09,
                        REGSNSHI   = 0x0B,
                        REGSNSLO   = 0x0D,
                        REGINTSRC  = 0x0F}
 
    static BANK_B = {   REGDATA    = 0x00,
                        REGDIR     = 0x02,
                        REGPULLUP  = 0x04,
                        REGPULLDN  = 0x06,
                        REGINTMASK = 0x08,
                        REGSNSHI   = 0x0A,
                        REGSNSLO   = 0x0C,
                        REGINTSRC  = 0x0E}
 
    constructor(i2c, address=0x40){
        base.constructor(i2c, address);
        _callbacks.resize(16,null);
        this.reset();
        this.clearAllIrqs();
    }
    
    //Write registers to default values
    function reset(){
        writeReg(BANK_A.REGDIR, 0xFF);
        writeReg(BANK_A.REGDATA, 0xFF);
        writeReg(BANK_A.REGPULLUP, 0x00);
        writeReg(BANK_A.REGPULLDN, 0x00);
        writeReg(BANK_A.REGINTMASK, 0xFF);
        writeReg(BANK_A.REGSNSHI, 0x00);
        writeReg(BANK_A.REGSNSLO, 0x00);
        
        writeReg(BANK_B.REGDIR, 0xFF);
        writeReg(BANK_B.REGDATA, 0xFF);
        writeReg(BANK_B.REGPULLUP, 0x00);
        writeReg(BANK_B.REGPULLDN, 0x00);
        writeReg(BANK_A.REGINTMASK, 0xFF);
        writeReg(BANK_B.REGSNSHI, 0x00);
        writeReg(BANK_B.REGSNSLO, 0x00);
    }
 
    function debug(){
        server.log(format("A-DATA   (0x%02X): 0x%02X",BANK_A.REGDATA, readReg(BANK_A.REGDATA)));
        imp.sleep(0.1);
        server.log(format("A-DIR    (0x%02X): 0x%02X",BANK_A.REGDIR, readReg(BANK_A.REGDIR)));
        imp.sleep(0.1);
        server.log(format("A-PULLUP (0x%02X): 0x%02X",BANK_A.REGPULLUP, readReg(BANK_A.REGPULLUP)));
        imp.sleep(0.1);
        server.log(format("A-PULLDN (0x%02X): 0x%02X",BANK_A.REGPULLDN, readReg(BANK_A.REGPULLDN)));
        imp.sleep(0.1);
        server.log(format("A-INTMASK (0x%02X): 0x%02X",BANK_A.REGINTMASK, readReg(BANK_A.REGINTMASK)));
        imp.sleep(0.1);
        server.log(format("A-SNSHI  (0x%02X): 0x%02X",BANK_A.REGSNSHI, readReg(BANK_A.REGSNSHI)));
        imp.sleep(0.1);
        server.log(format("A-SNSLO  (0x%02X): 0x%02X",BANK_A.REGSNSLO, readReg(BANK_A.REGSNSLO)));
        imp.sleep(0.1);
        server.log(format("B-DATA   (0x%02X): 0x%02X",BANK_B.REGDATA, readReg(BANK_B.REGDATA)));
        imp.sleep(0.1);
        server.log(format("B-DIR    (0x%02X): 0x%02X",BANK_B.REGDIR, readReg(BANK_B.REGDIR)));
        imp.sleep(0.1);
        server.log(format("B-PULLUP (0x%02X): 0x%02X",BANK_B.REGPULLUP, readReg(BANK_B.REGPULLUP)));
        imp.sleep(0.1);
        server.log(format("B-PULLDN (0x%02X): 0x%02X",BANK_B.REGPULLDN, readReg(BANK_B.REGPULLDN)));
        imp.sleep(0.1);
        server.log(format("B-INTMASK (0x%02X): 0x%02X",BANK_B.REGINTMASK, readReg(BANK_B.REGINTMASK)));
        imp.sleep(0.1);
        server.log(format("B-SNSHI  (0x%02X): 0x%02X",BANK_B.REGSNSHI, readReg(BANK_B.REGSNSHI)));
        imp.sleep(0.1);
        server.log(format("B-SNSLO  (0x%02X): 0x%02X",BANK_B.REGSNSLO, readReg(BANK_B.REGSNSLO)));
        
        // imp.sleep(0.1);
        // foreach(idx,val in BANK_A){
        //     server.log(format("Bank A %s (0x%02X): 0x%02X", idx, val, readReg(val)));
        //     imp.sleep(0.1);
        // }
        // foreach(idx,val in BANK_B){
        //     server.log(format("Bank B %s (0x%02X): 0x%02X", idx, val, readReg(val)));
        //     imp.sleep(0.1);
        // }
        // for(local i =0; i < 0x2F; i++){
        //     server.log(format("0x%02X: 0x%02X", i, readReg(i)));
        // }
 
    }
 
    function bank(gpio){
        return (gpio > 7) ? BANK_B : BANK_A;
    }
 
    // configure whether edges trigger an interrupt for specified GPIO
    function setIrqEdges( gpio, rising, falling) {
        local bank = bank(gpio);
        gpio = gpio % 8;
        local mask = 0x03 << ((gpio & 3) << 1);
        local data = (2*falling + rising) << ((gpio & 3) << 1);
        writeMasked(gpio >= 4 ? bank.REGSNSHI : bank.REGSNSLO, data, mask);
    }
 
    function clearAllIrqs() {
        writeReg(BANK_A.REGINTSRC,0xff);
        writeReg(BANK_B.REGINTSRC,0xff);
    }
 
    function getIrq(){
        return ((readReg(BANK_B.REGINTSRC) & 0xFF) << 8) | (readReg(BANK_A.REGINTSRC) & 0xFF);
    }
}

class ExpGPIO{
    _expander = null;  //Instance of an Expander class
    _gpio     = null;  //Pin number of this GPIO pin
    
    constructor(expander, gpio) {
        _expander = expander;
        _gpio     = gpio;
    }
    
    //Optional initial state (defaults to 0 just like the imp)
    function configure(mode, callback = null, initialstate=0) {
        // set the pin direction and configure the internal pullup resistor, if applicable
        _expander.setPin(_gpio,initialstate);
        if (mode == DIGITAL_OUT) {
            _expander.setDir(_gpio,1);
            _expander.setPullUp(_gpio,0);
        } else if (mode == DIGITAL_IN) {
            _expander.setDir(_gpio,0);
            _expander.setPullUp(_gpio,0);
        } else if (mode == DIGITAL_IN_PULLUP) {
            _expander.setDir(_gpio,0);
            _expander.setPullUp(_gpio,1);
        }
        
        // configure the pin to throw an interrupt, if necessary
        if (callback) {
            _expander.setIrqMask(_gpio,1);
            _expander.setIrqEdges(_gpio,1,1);
            _expander.setCallback(_gpio,callback);            
        } else {
            _expander.setIrqMask(_gpio,0);
            _expander.setIrqEdges(_gpio,0,0);
            _expander.setCallback(_gpio,null);
        }
    }
    
    function write(state) { _expander.setPin(_gpio,state); }
    
    function read() { return _expander.getPin(_gpio); }
}

// PN532 Device Driver
const PN532_PREAMBLE            = 0x00;
const PN532_STARTCODE2          = 0xFF;
const PN532_POSTAMBLE           = 0x00;

const PN532_HOSTTOPN532         = 0xD4;

const PN532_FIRMWAREVERSION     = 0x02;
const PN532_SAMCONFIGURATION    = 0x14;
const PN532_RFCONFIGURATION     = 0x32;

const PN532_SPI_STATREAD        = 0x02;
const PN532_SPI_DATAWRITE       = 0x01;
const PN532_SPI_DATAREAD        = 0x03;
const PN532_SPI_READY           = 0x01;

const PN532_MAX_RETRIES         = 0x05;

class PN532 {
    spi      = null;
    nfc_cs_l = null;
    nfc_pd_l = null;
    
    device_id   = null;
    device_id_a = null;
    device_id_b = null;
    device_id_c = null;
    
    pn532_ack = [0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00];
    pn532_firmware_version = [0x00, 0xFF, 0x06, 0xFA, 0xD5, 0x03];

    response_buffer = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19];
    booted = true;
    
    constructor(_spi, _nfc_cs_l, _nfc_pd_l) {
        device_id   = hardware.getimpeeid().slice(10);
        device_id_a = hex_to_i(device_id.slice(0,2));
        device_id_b = hex_to_i(device_id.slice(2,4));
        device_id_c = hex_to_i(device_id.slice(4,6));
        
        spi      = _spi;
        nfc_cs_l = _nfc_cs_l;
        nfc_pd_l = _nfc_pd_l;
    }
    
    ///////////////////////////////////////
    // NFC SPI Functions
    function spi_start() {
        // Configure SPI at about 4MHz
        spi.configure(LSB_FIRST | CLOCK_IDLE_HIGH, 4000);
    
        nfc_cs_l.configure(DIGITAL_OUT); // Configure the chip select pin
        nfc_cs_l.write(1);               // pull CS high
        imp.sleep(0.1);                  // wait 100 ms
        nfc_cs_l.write(0);               // pull CS low to start the transmission of data
        imp.sleep(0.1);
        //server.log("SPI Init successful");
    }
    
    function spi_stop() {
        spi.configure(CLOCK_IDLE_LOW | MSB_FIRST | CLOCK_2ND_EDGE, SPICLK);
    }
    
    function spi_read_ack() {
        spi_read_data(6);
        for (local i = 0; i < 6; i++) {
            if (response_buffer[i] != pn532_ack[i])
                return false;
        }
    
        return true;
    }
    
    function spi_read_data(length) {
        nfc_cs_l.write(0); // pull CS low
        imp.sleep(0.002);
        spi_write(PN532_SPI_DATAREAD); // read leading byte DR and discard
    
        local response = "";
        for (local i = 0; i < length; i++) {
            imp.sleep(0.001);
            response_buffer[i] = spi_write(PN532_SPI_STATREAD);
            response = response + response_buffer[i] + " ";
        }
    
        //server.log("spi_read_data: " + response);
        nfc_cs_l.write(1); // pull CS high
    }
    
    function spi_read_status() {
        nfc_cs_l.write(0); // pull CS low
        imp.sleep(0.002);
    
        // Send status command to PN532; ignore returned byte
        spi_write(PN532_SPI_STATREAD);
    
        // Collect status response, send junk 0x00 byte
        local value = spi_write(0x00);
        nfc_cs_l.write(1); // pull CS high
    
        return value;
    }
    
    function spi_write_command(cmd, cmdlen) {
        local checksum;
        nfc_cs_l.write(0); // pull CS low
        imp.sleep(0.002);
        cmdlen++;
    
        spi_write(PN532_SPI_DATAWRITE);
    
        checksum = PN532_PREAMBLE + PN532_PREAMBLE + PN532_STARTCODE2;
        spi_write(PN532_PREAMBLE);
        spi_write(PN532_PREAMBLE);
        spi_write(PN532_STARTCODE2);
    
        spi_write(cmdlen);
        local cmdlen_1 = 256 - cmdlen;
        spi_write(cmdlen_1);
    
        spi_write(PN532_HOSTTOPN532);
        checksum += PN532_HOSTTOPN532;
    
        for (local i = 0; i < cmdlen - 1; i++) {
            spi_write(cmd[i]);
            checksum += cmd[i];
        }
    
        checksum %= 256;
        local checksum_1 = 255 - checksum;
        spi_write(checksum_1);
        spi_write(PN532_POSTAMBLE);
    
        nfc_cs_l.write(1); // pull CS high
    }
    
    function spi_write(byte) {
        // Write the single byte
        spi.write(format("%c", byte));
    
        // Collect the response from the holding register
        local resp = spi.read(1);
    
        // Show what we sent
        //server.log(format("SPI tx %02x, rx %02x", byte, resp[0]));
    
        // Return the byte
        return resp[0];
    }
    
    ////////////////////////////////////
    // PN532 functions
    function nfc_init() {
        spi_start();
        
        nfc_pd_l.write(1); // Power down high
        nfc_cs_l.write(0); // pull CS low
        imp.sleep(0.1);
    
        // No need for this at the moment but it's useful for debugging.
        if (!nfc_get_firmware_version()) {
            server.log("Didn't find PN53x chip");
            booted = false;
        }
    
        if (!nfc_SAM_config()) {
            server.log("SAM config error");
            booted = false;
        }
        
        spi_stop();
    }
    
    function nfc_get_firmware_version() {
        //server.log("Getting firmware version");
    
        if (!send_command_check_ready([PN532_FIRMWAREVERSION], 1,100))
            return 0;
        spi_read_data(12);
    
        for (local i = 0; i < 6; i++) {
            if (response_buffer[i] != pn532_firmware_version[i])
                return false;
        }
    
        server.log(format("NFC chip: PN5%02x", response_buffer[6]));
        //server.log("Firmware ver "+ response_buffer[7] + "." + response_buffer[8]);
        //server.log(format("Supports %02x", response_buffer[9]));
    
        return true;
    }
    
    function nfc_SAM_config() {
        //server.log("SAM configuration");
        if (!send_command_check_ready([PN532_SAMCONFIGURATION, 0x01, 0x14, 0x01], 4, 100))
            return false;
    
        spi_read_data(8);
        if (response_buffer[5] == 0x15) return true;
        else return false;
    }
    
    function nfc_scan() {
        //server.log("nfc_p2p_scan");
        send_command_check_ready([PN532_RFCONFIGURATION, PN532_MAX_RETRIES, 0xFF, 0x01, 0x14], 5, 100);
        if (!send_command_check_ready([
            0x4A,                // InListPassivTargets
            0x01,                // Number of cards to init (if in field)
            0x00,                // Baud rate (106kbit/s)
            ], 3, 100)) {
            error("Unknown error detected during nfc_p2p_scan");
            return false;
        }
    
        spi_read_data(18);
    
        if (response_buffer[7] > 0) {
            local tag = format("%02x%02x%02x", response_buffer[14], response_buffer[15], response_buffer[16]);
            return tag
        }
    
        return null;
    }
    
    function nfc_power_down() {
        //server.log("nfc_power_down");
        if (!send_command_check_ready([
            0x16,                // PowerDown
            0x20,                // Only wake on SPI
            ], 2, 100)) {
            server.log("Unknown error detected during nfc_power_down");
            return false;
        }
    
        spi_read_data(9);
    }
    
    // This command configures the NFC chip to act as a target, much like a standard
    // dumb prox card.  The ID sent depends on the baud rate.  We're using 106kbit/s
    // so the NFCID1 will be sent (3 bytes).
    function nfc_p2p_target() {
        //server.log("nfc_p2p_target");
        if (!send_command([
            0x8C,                                   // TgInitAsTarget
            0x00,                                   // Accepted modes, 0 = all
            0x08, 0x00,                             // SENS_RES
            device_id_a, device_id_b, device_id_c,  // NFCID1
            0x40,                                   // SEL_RES
            0x01, 0xFE, 0xA2, 0xA3,                 // Parameters to build POL_RES (16 bytes)
            0xA4, 0xA5, 0xA6, 0xA7,
            0xC0, 0xC1, 0xC2, 0xC3,
            0xC4, 0xC5, 0xC6, 0xC7,
            0xFF, 0xFF,
            0xAA, 0x99, 0x88, 0x77,                 // NFCID3t
            0x66, 0x55, 0x44, 0x33,
            0x22, 0x11,
            0x00,                                   // General bytes
            0x00                                    // historical bytes
            ], 38, 100)) {
            server.log("Unknown error detected during nfc_p2p_target");
            return false;
        }
    }
    
    function send_command_check_ready(cmd, cmdlen, timeout) {
        return send_command(cmd, cmdlen, timeout) && check_ready(timeout);
    }
    
    function send_command(cmd, cmdlen, timeout) {
        local timer = 0;
    
        spi_write_command(cmd, cmdlen);
    
        // Wait for chip to say its ready!
        while (spi_read_status() != PN532_SPI_READY) {
            if (timeout != 0) {
                timer += 10;
                if (timer > timeout) {
                    server.log("No response READY");
                    return false;
                }
            }
            imp.sleep(0.01);
        }
    
        // read acknowledgement
        if (!spi_read_ack()) {
            server.log("Wrong ACK");
            return false;
        }
    
        //server.log("read ack");
    
        return true;
    }
    
    function check_ready(timeout) {
        local timer = 0;
        // Wait for chip to say its ready!
        while (spi_read_status() != PN532_SPI_READY) {
            if (timeout != 0) {
                timer += 10;
                if (timer > timeout) {
                    server.log("No response READY");
                    return false;
                }
            }
            imp.sleep(0.01);
        }
    
        return true;
    }
    
    function hex_to_i(hex) {
        local result = 0;
        local shift = hex.len() * 4;
    
        // For each digit..
        for(local d = 0; d < hex.len(); d++) {
            local digit;
    
            // Convert from ASCII Hex to integer
            if(hex[d] >= 0x61)
                digit = hex[d] - 0x57;
            else if(hex[d] >= 0x41)
                 digit = hex[d] - 0x37;
            else
                 digit = hex[d] - 0x30;
    
            // Accumulate digit
            shift -= 4;
            result += digit << shift;
        }
    
        return result;
    }
    
    function scan_and_sleep() {
        if (booted) {
            spi_start();
    
            // Scan for nearby NFC devices
            local tag_detected = nfc_scan();
    
            // Enter target mode.  This allows other readers to read our id.
            nfc_p2p_target();
            
            spi_stop();
            
            return tag_detected;
        } else {
            server.error("PN532 could not be initialized, halting.");
            return false;
        }
    }
}

const WIDTH          = 264;
const HEIGHT         = 176;
const PIXELS         = 46464;
const BYTESPERSCREEN = 5808;
const BYTESPERLINE   = 33;
const BYTESPERSCAN   = 44;
const CHARCHAR       = "%c%c";
const BYTE           = 'b';
const SLOTS          = 0;
const LINES          = 1;
const WHITE_PIXEL    = 0xaa;
const BLACK_PIXEL    = 0xff;
const NOTHING_PIXEL  = 0x00;
const INVERSE        = 0xff;
const NORMAL         = 0x00;
const REPEAT         = 2;
const STEP           = 4;
const BLOCK          = 32;

class Epaper {
    /*
     * class to drive Pervasive Displays epaper display
     * see http://repaper.org
     */
    LINEHEADER       = null;

    spi              = null;
    epd_cs_l         = null;
    busy             = null;
    therm            = null;
    pwm              = null;
    rst_l            = null;
    pwr_en_l         = null;
    border           = null;
    discharge        = null;
    
    epd_cs_l_write   = null;
    spi_write        = null;
    
    line_data        = null;
    scan_line_data   = null;
    line_cache       = null;
    line_cache_ptr   = null;
    line_cache_slots = null;
    line_cache_lines = null;
    scan_table       = null;
    
    black_line       = null;
    white_line       = null;
    nothing_line     = null;
    
    writer           = null;
    
    booted           = false;

    constructor(width, height, spi, epd_cs_l, busy, therm, pwm, rst_l, pwr_en_l, discharge, border) {
        this.LINEHEADER     = format("%c%c", 0x70, 0x0A);
        
        epd_cs_l_write = epd_cs_l.write.bindenv(epd_cs_l);
        spi_write      = spi.write.bindenv(spi);
        
        // Initialize the various caches
        local line_data_size = (width / 8) + (height / 4) + 2;
        line_data = blob(line_data_size);
        line_cache = array(32);
        for (local i = 0; i < 32; i++ ) {
            line_cache[i] = blob(line_data_size);
        }
        
        line_cache_ptr   = 0;
        line_cache_lines = {};
        line_cache_slots = {};
        
        scan_line_data = blob(BYTESPERSCAN);
        
        white_line = junk_line(WHITE_PIXEL, BYTESPERLINE);
        black_line = junk_line(BLACK_PIXEL, BYTESPERLINE);
        nothing_line = junk_line(0x00, BYTESPERLINE);

        writer = line_data.writen.bindenv(line_data);
        
        // initialize the SPI bus
        // this is tricky since we're likely sharing it with the SPI flash. Need to use a clock speed that both
        // are ok with, or reconfigure the bus on every transaction
        // As it turns out, the ePaper display is content with 4 MHz to 12 MHz, all of which are ok with the flash
        // Furthermore, the display seems to work just fine at 15 MHz.
        this.spi = spi;
        //server.log("Display Running at: " + this.spiOff() + " kHz");
        
        this.epd_cs_l = epd_cs_l;
        this.epd_cs_l.configure(DIGITAL_OUT);
        //this.epd_cs_l.write(0);

        // initialize the other digital i/o needed by the display
        this.busy = busy;
        this.busy.configure(DIGITAL_IN);

        this.therm = therm;

        this.rst_l = rst_l;
        this.rst_l.configure(DIGITAL_OUT);
        //this.rst_l.write(1);

        this.pwr_en_l = pwr_en_l;
        this.pwr_en_l.configure(DIGITAL_OUT);
        //this.pwr_en_l.write(1);

        this.discharge = discharge;
        this.discharge.configure(DIGITAL_OUT);
        //this.discharge.write(0);

        this.border = border;
        this.border.configure(DIGITAL_OUT);
        //this.border.write(0);

        // must call this to release the spi bus
        this.epd_cs_l.write(1);
    }

    // enable SPI
    function spiOn() {
        local freq = this.spi.configure(CLOCK_IDLE_HIGH | MSB_FIRST | CLOCK_2ND_EDGE, SPICLK);
        this.spi.write("\x00");
        imp.sleep(0.00001);
        //server.log("running at " + freq);
        return freq;
    }

    // disable SPI
    function spiOff() {
        local freq = this.spi.configure(CLOCK_IDLE_LOW | MSB_FIRST | CLOCK_2ND_EDGE, SPICLK);

        return freq;
    }
    
    function itos_pair(a, b) {
      local result = blob(2);
      result[0] = a;
      result[1] = b;
      return result;
    }

    // Write to EPD registers over SPI
    function writeEPD(index, ...) {
        epd_cs_l_write(1);                      // CS = 1
        epd_cs_l_write(0);                      // CS = 0
        spi_write(itos_pair(0x70, index));
        epd_cs_l_write(1);                      // CS = 1
        epd_cs_l_write(0);                      // CS = 0
        spi_write(format("%c", 0x72));          // Write data header
        //spi_write(itos_pair(0x72, value));
        
        foreach (word in vargv) {
            spi_write(format("%c", word));      // then register data
        }
        
        epd_cs_l_write(1);                      // CS = 1
    }
    
    function write_epd_pair(index, value) {
        epd_cs_l_write(1);                        // CS = 1
        epd_cs_l_write(0);                        // CS = 0
        spi_write(itos_pair(0x70, index));
        epd_cs_l_write(1);                        // CS = 1
        epd_cs_l_write(0);                        // CS = 0
        spi_write(itos_pair(0x72, value));
        epd_cs_l_write(1);                        // CS = 1
    }
    
    function writeEPD_raw(...) {
        imp.sleep(0.00001);
        epd_cs_l_write(0);                      // CS = 0

        foreach (word in vargv) {
            spi_write(format("%c", word));      // then register data
        }
        
        epd_cs_l_write(1);                      // CS = 1
    }
    
    function readEPD(...) {
        local result = "";

        imp.sleep(0.00001);
        this.epd_cs_l.write(0);                      // CS = 0
        
        foreach (word in vargv) {
            result += this.spi.writeread(format("%c", word));
        }
        
        this.epd_cs_l.write(1);                      // CS = 1
        
        return result;
    }
    
    // Power on COG Driver
    function start() {
        server.log("Powering On EPD.");

        /* POWER-ON SEQUENCE ------------------------------------------------*/

        // make sure SPI is low to avoid back-powering things through the SPI bus
        this.spiOn();

        // Make sure signals start unasserted (rest, panel-on, discharge, border, cs)
        this.pwr_en_l.write(1);
        this.rst_l.write(0);
        this.discharge.write(0);
        this.border.write(0);
        this.epd_cs_l.write(0);

        // Turn on panel power
        this.pwr_en_l.write(0);
        this.rst_l.write(1);
        this.border.write(1);
        this.epd_cs_l.write(1);
        imp.sleep(0.005);
        
        // send reset pulse
        this.rst_l.write(0);
        imp.sleep(0.005);
        
        this.rst_l.write(1);
        imp.sleep(0.005);
        
        // Initialize COG Driver
        // Wait for screen to be ready
        while (busy.read()) {
            server.log("Waiting for COG Driver to Power On...");
            imp.sleep(0.005);
        }
        
        // Check COG ID
        local cog_id = readEPD(0x71, 0x00)[1];
        //server.log("Cog ID: " + cog_id);
        if (0x02 != (0x0f & cog_id)) {
            server.error("Invalid Display Version")
            this.stop();
            // TODO led error
            return;
        }
        
        // Disable OE
        this.writeEPD(0x02, 0x40);
        
        // Check Breakage - TODO
        //server.log(readEPD(0x0F,0x00));
        
        //Power Saving Mode
        this.writeEPD(0x0b, 0x02);
        
        // Channel Select for 2.7" Display
        this.writeEPD(0x01,0x00,0x00,0x00,0x7F,0xFF,0xFE,0x00,0x00);

        // High Power Mode Oscillator Setting
        this.writeEPD(0x07, 0xd1);
        
        // Power Setting
        this.writeEPD(0x08, 0x02);
        
        // Set Vcom level
        this.writeEPD(0x09, 0xc2);

        // power setting
        this.writeEPD(0x04, 0x03);

        // Driver latch on ("cancel register noise")
        this.writeEPD(0x03, 0x01);

        // Driver latch off
        this.writeEPD(0x03, 0x00);

        imp.sleep(0.05);
        
        local dc_ok = false;
        
        for (local i = 0; i < 4; i++) {
            // Start charge pump positive V (VGH & VDH on)
            this.writeEPD(0x05, 0x01);

            imp.sleep(0.240);

            // Start charge pump negative voltage
            this.writeEPD(0x05, 0x03);

            imp.sleep(0.040);

            // Set charge pump Vcom driver to ON
            this.writeEPD(0x05, 0x0f);

            imp.sleep(0.040);
            
            writeEPD_raw(0x70, 0x0f);
            local dc_state = readEPD(0x73, 0x00)[1];
            //server.log("dc state: " + dc_state);
            if (0x40 == (0x40 & dc_state)) {
                dc_ok = true;
                break;
            }
        }
        
        if (!dc_ok) {
            server.error("DC state failed");
            
            // Output enable to disable
            this.writeEPD(0x02, 0x40);
            
            this.stop();
            
            // TODO led error blink
            return;
        }
        
        booted = true;

        server.log("COG Driver Initialized.");
    }

    // Power off COG Driver
    function stop() {
        server.log("Powering Down EPD");
        // delay 25ms
        //imp.sleep(0.025);

        // set BORDER low for 200 ms
        this.border.write(0);
        imp.sleep(0.2);
        this.border.write(1);
        
        // Check DC/DC
        //server.log("Check DC/DC on EPD Power off: (0x40)");
        writeEPD_raw(0x70, 0x0f);
        local dc_state = readEPD(0x73, 0x00)[1];
        //server.log("dc state: " + dc_state);
        if (0x40 != (0x40 & dc_state)) {ly
            server.log("dc failed");
            return;
        }

        // latch reset on
        this.writeEPD(0x03, 0x01);

        //output enable off
        this.writeEPD(0x02, 0x05);

        // VCOM power off
        this.writeEPD(0x05, 0x03);

        // power off negative charge pump
        this.writeEPD(0x05, 0x01);
        
        imp.sleep(0.240);
        
        // power off all charge pumps
        this.writeEPD(0x05, 0x00);
        
        // turn off oscillator
        this.writeEPD(0x07, 0x01);

        // discharge internal on
        writeEPD(0x04, 0x83);

        imp.sleep(0.030);

        // turn off all power and set all inputs low
        this.rst_l.write(0);
        this.pwr_en_l.write(1);
        this.border.write(0);

        // ensure MOSI is low before CS Low
        this.spiOff();
        imp.sleep(0.001);
        this.epd_cs_l.write(0);

        // send discharge pulse
        //server.log("Discharging Rails");
        this.discharge.write(1);
        imp.sleep(0.15);
        this.discharge.write(0);
        
        this.epd_cs_l.write(1);

        server.log("Display Powered Down.");
    }
    
    function cache_line(line, data) {
        local slot = line_cache_ptr++ % BLOCK;
        
        line_cache_lines[line] <- slot;
        if (slot in line_cache_slots) {
            local old_line = line_cache_slots[slot];
            delete line_cache_lines[old_line];
        }
        line_cache_slots[slot] <- line;
        
        line_cache[slot].seek(0);
        line_cache[slot].writeblob(data);
    }
    
    function get_cached_line(line) {
        if (line in line_cache_lines) {
            return line_cache[line_cache_lines[line]];
        } else {
            return false;
        }
    }
    
    function clear_cache() {
        line_cache_lines.clear();
        line_cache_slots.clear();
        
        line_cache_ptr = 0;
    }
    
    // draw a line on the screen
    function write_line(line, data, inverse, cache_lines = true, set_voltage_limit = false) {
        local pixels;

        if (set_voltage_limit) {
            // charge pump voltage level reduce voltage shift
            write_epd_pair(0x04, 0x00);
        }

        line_data.seek(0);

        if (data == BLACK_PIXEL || data == WHITE_PIXEL || data == NOTHING_PIXEL) {
            if (data == WHITE_PIXEL) {
                pixels = white_line;
            } else if (data == BLACK_PIXEL) {
                pixels = black_line;
            } else {
                pixels = nothing_line;
            }

            writer(0x72, BYTE);
            
            // Null border byte
            writer(0x00, BYTE);
            
            // Odd pixels
            line_data.writeblob(pixels);

            // Scan Lines
            local scan_pos = (HEIGHT - line - 1) >> 2;
            local scan_shift = 0x03 << ((line & 0x03) << 1);

            // Set the scan line, write the blob, then reset to 0
            scan_line_data[scan_pos] = scan_shift;
            line_data.writeblob(scan_line_data);
            scan_line_data[scan_pos] = 0x00;
            
            // Even Pixels
            line_data.writeblob(pixels);
        } else {
            local cached_line = get_cached_line(line);
      
            if (cached_line) {
                line_data.writeblob(cached_line);
            } else {
                writer(0x72, BYTE);
              
                // Null border byte
                writer(0x00, BYTE);
              
                // Odd pixels
                for (local i = BYTESPERLINE - 1; i > -1 && i < data.len(); i--) {
                    pixels = (data[i]>>1) ^ inverse | 0xaa;

                    pixels = ((pixels & 0xc0) >> 6)
                           | ((pixels & 0x30) >> 2)
                           | ((pixels & 0x0c) << 2)
                           | ((pixels & 0x03) << 6);
                           
                    writer(pixels, BYTE);
                }
                  
                // Scan Lines
                local scan_pos = (HEIGHT - line - 1) >> 2;
                local scan_shift = 0x03 << ((line & 0x03) << 1);
    
                // Set the scan line, write the blob, then reset to 0
                scan_line_data[scan_pos] = scan_shift;
                line_data.writeblob(scan_line_data);
                scan_line_data[scan_pos] = 0x00;
              
                // Even Pixels
                for (local i = 0; i < BYTESPERLINE && i < data.len(); i++) {
                    pixels = data[i] ^ inverse | 0xaa;
                    writer(pixels, BYTE);
                }

                if (cache_lines) {
                    cache_line(line, line_data);
                }
            }
        }
        
        // read from start of line
        line_data.seek(0);
    
        // Send index "0x0A" and keep CS asserted
        epd_cs_l_write(0);                      // CS = 0
        spi_write(LINEHEADER);
        epd_cs_l_write(1);                      // CS = 1
        epd_cs_l_write(0);                      // CS = 0
        
        spi_write(line_data);
        
        epd_cs_l_write(1);
    
        // Turn on output enable
        write_epd_pair(0x02, 0x07);
    }

    // draw an image
    function draw_image(data) {
        this.frame_data_13(data, INVERSE);
        this.frame_stage_2();
        this.frame_data_13(data, NORMAL);
    }
    
    function draw_image_range(data, start, end) {
        frame_data_13_range(data, INVERSE, start, end);
        frame_stage_2_range(start, end);
        frame_data_13_range(data, NORMAL, start, end);
    }
    
    function frame_data_13_range(data, inverse, start, end) {
        local total_lines = end - start;
        clear_cache();
        
        for (local i = 0; i < REPEAT; i++) {
            local block_begin = start;
            local block_end   = start + BLOCK;
            
            if (end < block_end) {
                block_end = end;
            }
            
            data.seek(0);
            
            if (start > 0) {
                write_line(start - 1, WHITE_PIXEL, NORMAL, false);
                write_line(start - 1, WHITE_PIXEL, NORMAL, false);
            }
            
            while (block_begin < end) {
                //server.log("block begin = " + block_begin + " block_end = " + block_end);
                for (local j = block_begin; j < block_end; j++) {
                    data.seek((j - start) * BYTESPERLINE);
                    write_line(j, data.readblob(BYTESPERLINE), inverse, false);
                }
                
                block_begin = block_begin + STEP;
                block_end   = block_end + STEP;
                
                if (block_end > end) {
                    block_end = end;
                }
            }
            
            if (end < HEIGHT) {
                write_line(end, WHITE_PIXEL, NORMAL, false);
                write_line(end, WHITE_PIXEL, NORMAL, false);
            }
        }
    }
    
    function frame_stage_2_range(start, end) {
        clear_cache();
        
        for (local i = 0; i < 4; i++) {
            frame_fixed_timed(BLACK_PIXEL, 196, start, end);
            frame_fixed_timed(WHITE_PIXEL, 196, start, end);
        }
    }
    
    function frame_data_13(data, inverse) {
        clear_cache();
        
        for (local i = 0; i < REPEAT; i++) {
            local block_begin = 0;
            local block_end   = BLOCK;
            
            data.seek(0);
            
            while (block_begin < HEIGHT) {
                for (local j = block_begin; j < block_end; j++) {
                    if (j*BYTESPERLINE + BYTESPERLINE < data.len()) {
                      data.seek(j * BYTESPERLINE);
                      write_line(j, data.readblob(BYTESPERLINE), inverse, false);
                    }
                }
                
                block_begin = block_begin + STEP;
                block_end   = block_end + STEP;
                
                if (block_end > HEIGHT) {
                    block_end = HEIGHT;
                }
            }
        }
    }
    
    function junk_line(value, size) {
        local junk = blob(size);
        
        for (local i = 0; i < size; i++) {
            junk.writen(value, BYTE);
        }
        
        return junk;
    }
    
    function frame_stage_2() {
        clear_cache();
        
        for (local i = 0; i < 4; i++) {
            frame_fixed_timed(BLACK_PIXEL, 196, 0, HEIGHT);
            frame_fixed_timed(WHITE_PIXEL, 196, 0, HEIGHT);
        }
    }
    
    function frame_fixed_timed(data, stage_time, start, end) {
       while (stage_time > 0) {
            local start_time = hardware.millis();
            
            for (local i = start; i < end; i++) {
                write_line(i, data, NORMAL, false);
            }
            
            local end_time = hardware.millis();
            stage_time = stage_time - end_time - start_time;
        }
    }

    function getTemp() {
        return therm.read_c();
    }
}

class Thermistor {
        // thermistor constants are shown on your thermistor datasheet
        // beta value (for the temp range your device will operate in)
        b_therm                 = null;
        t0_therm                = null;
        // nominal resistance of the thermistor at room temperature
        r0_therm                = null;

        // analog input pin
        p_therm                 = null;
        points_per_read         = null;

        high_side_therm         = null;

        constructor(pin, b, t0, r, points = 10, _high_side_therm = true) {
                this.p_therm = pin;
                this.p_therm.configure(ANALOG_IN);

                // force all of these values to floats in case they come in as integers
                this.b_therm = b * 1.0;
                this.t0_therm = t0 * 1.0;
                this.r0_therm = r * 1.0;
                this.points_per_read = points * 1.0;

                this.high_side_therm = _high_side_therm;
        }

        // read thermistor in Kelvin
        function read() {
                local vdda_raw = 0;
                local vtherm_raw = 0;
                for (local i = 0; i < points_per_read; i++) {
                        vdda_raw += hardware.voltage();
                        vtherm_raw += p_therm.read();
                }
                local vdda = (vdda_raw / points_per_read);
                local v_therm = (vtherm_raw / points_per_read) * (vdda / 65535.0);
                local r_therm = 0;        
                if (high_side_therm) {
                        r_therm = (vdda - v_therm) * (r0_therm / v_therm);
                } else {
                        r_therm = r0_therm / ((vdda / v_therm) - 1);
                }

                local ln_therm = math.log(r0_therm / r_therm);
                local t_therm = (t0_therm * b_therm) / (b_therm - t0_therm * ln_therm);
                return t_therm;
        }

        // read thermistor in Celsius
        function read_c() {
                return this.read() - 273.15;
        }

        // read thermistor in Fahrenheit
        function read_f() {
                local temp = this.read() - 273.15;
                return (temp * 9.0 / 5.0 + 32.0);
        }
}

class Backend {
    connecting = false;
    therm      = null;
    battery    = null;
    nv         = null;
    cold_boot  = true;
    
    constructor(_therm, _battery) {
        therm   = _therm;
        battery = _battery;
        
        // nv will be undefined if we're cold booting
        if ("nv" in getroottable()) {
            server.log(getroottable()["nv"].device_id + " waking up...");
            cold_boot = false;
        } else {
            imp.setpowersave(true);
            local device_id = hardware.getimpeeid().slice(10);
            server.log("Cold booting, my ID is " + device_id);
            
            // Created on demand
            getroottable()["nv"] <- {
                ["device_id"]     = device_id,
            };
        }
        
        nv = getroottable()["nv"];
    }
    
    function update_screen() {
        if (server.isconnected()) {
            get_screen(SERVER_CONNECTED);
        } else {
            connecting = true;
            server.connect(get_screen, CONNECT_TIMEOUT);
        }
    }
    
    function get_screen(state) {
        // If we're unable to connect, just go back to sleep for a bit
        if (state != SERVER_CONNECTED) {
            backend.connecting = false;
            return;
        }
        
        local data = {
            voltage = battery.read_voltage(),
            temp = therm.read_f(),
        }
        
        agent.send("screen", data);
    }
    
    function update_cat() {
        if (server.isconnected()) {
            get_cat(SERVER_CONNECTED);
        } else {
            connecting = true;
            server.connect(get_cat, CONNECT_TIMEOUT);
        }
    }
    
    function get_cat(state) {
        // If we're unable to connect, just go back to sleep for a bit
        if (state != SERVER_CONNECTED) {
            backend.connecting = false;
            return;
        }
        
        agent.send("cat", {});
    }
}

class Battery {
    vbat_sns_en = null;
    vbat_sns    = null;
    chg_status  = null;
    
    constructor(_vbat_sns_en, _vbat_sns, _chg_status) {
        vbat_sns_en = _vbat_sns_en;
        vbat_sns    = _vbat_sns;
        chg_status  = _chg_status;
    }
    
    function read_voltage() {
        vbat_sns_en.write(1);
        local vbat = (vbat_sns.read()/65535.0) * hardware.voltage() * (6.9/4.7);
        vbat_sns_en.write(0);
        
        return vbat;
    }
    
    function charge_status() {
        if (chg_status.read()) {
            return false;
        } else {
            return true;
        }
    }
}

const BUTTONR = 0;
const BUTTONL = 1;

function button_event(button, state) {
    if (state == 1) {
        return;
    }
    
    led.write(0);
    
    if (button == BUTTONL) {
        backend.update_screen();
    } else {
        backend.update_cat();
    }
}

/* REGISTER AGENT CALLBACKS -------------------------------------------------*/
agent.on("screen", function(data) {
    led.write(0);
    display.start();
    display.draw_image(data);
    display.stop();
    led.write(1);
});

// Beginning of execution
flash_cs_l  <- hardware.pinE;
spi         <- hardware.spi257;
i2c         <- hardware.i2c89;
ioexp_int   <- hardware.pin1;   // I/O Expander Alert

// Bus configs
spi.configure(CLOCK_IDLE_LOW | MSB_FIRST, SPICLK);
i2c.configure(CLOCK_SPEED_100_KHZ);

// Initialize the 16-channel I2C I/O Expander (SX1505)
ioexp <- SX1506(i2c, 0x40);    // instantiate I/O Expander

// PN532 pin config
nfc_cs_l <- ExpGPIO(ioexp, 8);
nfc_pd_l <- ExpGPIO(ioexp, 9);

nfc_cs_l.configure(DIGITAL_OUT);
nfc_pd_l.configure(DIGITAL_OUT);

nfc_cs_l.write(1);  // CS high
nfc_pd_l.write(0);  // Power down low

// Make GPIO instances for each IO on the expander
btn1 <- ExpGPIO(ioexp, 4);     // User Button 1 (GPIO 4)
btn2 <- ExpGPIO(ioexp, 5);     // User Button 2 (GPIO 5)
led  <- ExpGPIO(ioexp, 10);

// Initialize the interrupt Pin
ioexp_int.configure(DIGITAL_IN_WAKEUP, ioexp.callback.bindenv(ioexp));

// Flash pins
flash_cs_l.configure(DIGITAL_OUT);

epd_busy        <- hardware.pin6;         // Busy input
vbat_sns        <- hardware.pinA;         // Battery Voltage Sense (ADC)
vbat_sns.configure(ANALOG_IN);
temp_sns        <- hardware.pinB;         // Temperature Sense (ADC)
pwm             <- hardware.pinC;         // PWM Output for EPD (200kHz, 50% duty cycle)
epd_cs_l        <- hardware.pinD;         // EPD Chip Select (Active Low)
epd_pwr_en_l    <- ExpGPIO(ioexp, 0);     // EPD Panel Power Enable Low (GPIO 0)
epd_rst_l       <- ExpGPIO(ioexp, 1);     // EPD Reset Low (GPIO 1)
epd_discharge   <- ExpGPIO(ioexp, 2);     // EPD Discharge Line (GPIO 2)
epd_border      <- ExpGPIO(ioexp, 3);     // EPD Border CTRL Line (GPIO 3)


// Battery Charge Status on GPIO Expander
chg_status      <- ExpGPIO(ioexp, 6)
chg_status.configure(DIGITAL_IN);

// VBAT_SNS_EN on GPIO Expander
vbat_sns_en     <- ExpGPIO(ioexp, 7);
vbat_sns_en.configure(DIGITAL_OUT, 0);    // VBAT_SNS_EN (GPIO Expander Pin7)

// Initialize the thermistor
therm           <- Thermistor(temp_sns, 3340, 298, 10000);


// Initialize the battery
battery         <- Battery(vbat_sns_en, vbat_sns, chg_status);

// Log the battery voltage at startup
server.log(format("Battery Voltage: %.2f V", battery.read_voltage()));

// Initialize the backend
backend <- Backend(therm, battery);

// Initialize the epaper display
display <- Epaper(WIDTH, HEIGHT, spi, epd_cs_l, epd_busy, therm,
  pwm, epd_rst_l, epd_pwr_en_l, epd_discharge, epd_border);

// Configure the flash chip
flash <- SpiFlash(spi, flash_cs_l);
server.log(format("Flash Ready, mfg ID: 0x%02x, dev ID: 0x%02x", flash.mfgID, flash.devID));
flash.sleep();

// Configure the two buttons
btn1.configure(DIGITAL_IN, function(){ button_event(BUTTONL, btn1.read()); });
btn2.configure(DIGITAL_IN, function(){ button_event(BUTTONR, btn2.read()); });

// Configure the LED
led.configure(DIGITAL_OUT);
led.write(1);

// Configure and start the NFC chip
nfc <- PN532(spi, nfc_cs_l, nfc_pd_l);
nfc.nfc_init();

server.log("Current temp is " + therm.read_f());

// Fetch our main screen
backend.update_screen();

function flash_led_for_tag() {
        local delay = 0.05;
        
        led.write(0);
        imp.sleep(delay);
        led.write(1);
        imp.sleep(delay);
        led.write(0);
        imp.sleep(delay);
        led.write(1);
        imp.sleep(delay);
        led.write(0);
        imp.sleep(delay);
        led.write(1);
        imp.sleep(delay);
        led.write(0);
        imp.sleep(delay);
        led.write(1);
}

// Main lifecycle
function run_loop() {
    local tag_id = nfc.scan_and_sleep();
    
    if (tag_id != null) {
        server.log("Detected tag id: " + tag_id);
        flash_led_for_tag();
    }
    
    // See you soon!
    imp.wakeup(RUNLOOP_INTERVAL, run_loop.bindenv(this));
}; run_loop();
