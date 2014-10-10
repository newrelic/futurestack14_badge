
/*****************************************\
*        FUTURESTACK 14 BADGE DEMO        *
*           (c) 2014 New Relic            *
*                                         *
* For more information, see:              *
* github.com/newrelic/futurestack14_badge *
\*****************************************/

server.log("Running at " + http.agenturl());

const BACKEND_HOST = "https://futurestack.herokuapp.com";

/* URLS ---------------------------------------------------------------------*/
const URL_SCREEN     = "/v2/demo";
const URL_CAT        = "/v2/cat";

const WIDTH  = 264;
const HEIGHT = 176;

/* HTTP HELPERS -------------------------------------------------------------*/
function http_get(url) {
    local headers = {
        "Accept"       : "application/json",
    }
    
    local req = http.get(BACKEND_HOST + url, headers);
    local res = req.sendsync();
    
    if (res.statuscode != 200) {
        server.log("error getting " + BACKEND_HOST + url);
        return null;
    }
    
    return res.body;
}

function http_post(url, data) {
    local body = http.jsonencode(data);
    
    local headers = {
        "Content-Type" : "application/json",
        "Accept"       : "application/json",
    }

    local req = http.post(BACKEND_HOST + url, headers, body);
    local res = req.sendsync();
    
    if (res.statuscode != 200) {
        server.log("error sending message: " + res.body);
    } else {
        return res.body
    }
}

/* DEVICE EVENT HANDLERS ----------------------------------------------------*/
device.on("screen", function(data) {
    local req = http_post(URL_SCREEN, data);
    
    local data = blob();
    data.writestring(req);
    data.seek(0, 'b');
    
    device.send("screen", data);
});

device.on("cat", function(data) {
    local req = http_post(URL_CAT, data);
    
    local data = blob();
    data.writestring(req);
    data.seek(0, 'b');
    
    device.send("screen", data);
});

/* HTTP HANDLER -------------------------------------------------------------*/
http.onrequest(function(req, res) {
    server.log("Agent got new HTTP Request");
    // we need to set headers and respond to empty requests as they are usually preflight checks
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers","Origin, X-Requested-With, Content-Type, Accept");
    res.header("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    
    if (req.path == "/image") {
        // return right away to keep things responsive
        res.send(200, "OK");
        
        local data = blob(req.len());
        data.writestring(req.body);
        data.seek(0, 'b');
        local len = data.len();
        server.log("Got new image, length " + len);

        device.send("screen", data.readblob(len));
    } else {
        server.log("Agent got unknown request");
        res.send(200, "OK");
    }
});
