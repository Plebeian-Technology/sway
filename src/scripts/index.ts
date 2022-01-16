export * from "./testSendEmails";
import { default as congressional } from "./addCongressionalDistricts";
export { congressional };

export { default as geocodeGoogle } from "./geocodeGoogle";
export { downloadLocale } from "./testBucketDownload";
export { default as testFireClient } from "./testFireClient";
export { default as testFireFunction } from "./testFireFunction";
export { default as updateDistricts } from "./updateDistrictsAndCities";
export { default as congressJsonToCsv } from "./congressJsonToCsv";

const [
    _node, // path to node binary executing file
    _file, // path to file being executed (seed.js)
    _env,
    script, // locale name passed into seed.sh as $2
] = process.argv;

console.log("");
console.log("RUNNING SCRIPT NAME -", script);
console.log("NODE ENVIRONMENT    -", process.env.NODE_ENV);
console.log("");

if (script === "congress") {
    congressional().catch(console.error);
}
