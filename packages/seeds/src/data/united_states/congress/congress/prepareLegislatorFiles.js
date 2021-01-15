"use strict";
var __spreadArrays = (this && this.__spreadArrays) || function () {
    for (var s = 0, i = 0, il = arguments.length; i < il; i++) s += arguments[i].length;
    for (var r = Array(s), k = 0, i = 0; i < il; i++)
        for (var a = arguments[i], j = 0, jl = a.length; j < jl; j++, k++)
            r[k] = a[j];
    return r;
};
exports.__esModule = true;
var fs = require("fs");
var node_fetch_1 = require("node-fetch");
var constants_1 = require("@sway/constants");
// * PROPUBLICA_API_KEY: https://www.propublica.org/datastore/api/propublica-congress-api
// * GOOGLE_MAPS_API_KEY: https://developers.google.com/maps/documentation/embed/get-api-key
// * OPEN_STATES_API_KEY: https://openstates.org/api/register/
// * GEOCODIO_API_KEY: https://dash.geocod.io/login
// * IP_STACK_API_KEY: https://ipstack.com/signup/free
var CONGRESS = 117;
var PROPUBLICA_HEADERS = {
    Accept: "application/json",
    "Content-Type": "application/json",
    "X-API-Key": process.env.PROPUBLICA_API_KEY || ""
};
var reducer = function (sum, l) {
    var item = {
        street: l.office,
        city: "",
        region: "",
        regionCode: "",
        zip: "",
        first_name: l.first_name,
        last_name: l.last_name,
        externalId: l.first_name.toLowerCase() + "-" + l.last_name.toLowerCase() + "-2020",
        bioguideId: l.id,
        district: l.district ? Number(l.district) : 0,
        phone: l.phone,
        fax: l.fax,
        title: l.short_title,
        active: l.in_office,
        twitter: l.twitter_account,
        party: l.party,
        photoURL: process.env.CONGRESS_IMAGE_REPO_URL + "/" + l.id + ".jpg",
        link: l.url,
        email: l.contact_form
    };
    if (sum[l.state]) {
        sum[l.state].push(item);
    }
    else {
        sum[l.state] = [item];
    }
    return sum;
};
var house = process.env.PROPUBLICA_ORIGIN + "/" + CONGRESS + "/house/members.json";
var senate = process.env.PROPUBLICA_ORIGIN + "/" + CONGRESS + "/senate/members.json";
var get = function (url) {
    console.log("FETCHING URL -", url);
    return node_fetch_1["default"](url, { headers: PROPUBLICA_HEADERS })
        .then(function (res) { return res.json(); })
        .then(function (json) { return json.results[0].members.reduce(reducer, {}); })["catch"](console.error);
};
exports["default"] = (function () {
    return Promise.all([get(house), get(senate)])
        .then(function (_a) {
        var housers = _a[0], senators = _a[1];
        Object.keys(senators).forEach(function (state, index) {
            var _a;
            // if (index > 0) return;
            console.log("PREPARING LEGISLATORS FOR STATE -", state);
            var delegation = __spreadArrays(senators[state], housers[state]);
            var stateName = constants_1.STATE_CODES_NAMES[state].toLowerCase();
            var path = __dirname + "/" + stateName + "/legislators";
            if (!path.includes("congress")) {
                throw new Error("Invalid Directory Path does not have \"congress\" - " + path);
            }
            var data = {
                united_states: {
                    congress: (_a = {},
                        _a[stateName.toLowerCase()] = delegation,
                        _a)
                }
            };
            console.log("DATA FOR LEGISLATORS");
            console.log("WRITING DATA TO PATH -", path);
            // console.dir(data, { depth: null })
            fs.mkdir(path, { recursive: true }, function (err) {
                if (err)
                    throw err;
                console.log("CREATED DIRECTORY, WRITING FILE -", path + "/index.ts");
                fs.writeFile(path + "/index.ts", "export default " + JSON.stringify(data, null, 4), function (fileWriteError) {
                    if (fileWriteError)
                        throw fileWriteError;
                });
            });
        });
    })["catch"](console.error);
});
