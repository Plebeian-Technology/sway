import * as src from "./src";

const [
    node, // path to node binary executing file
    file, // path to file being executed (seed.js)
    env,
    script, // locale name passed into seed.sh as $2
] = process.argv;

console.log("");
console.log("RUNNING SCRIPT NAME -", script);
console.log("NODE ENVIRONMENT    -", process.env.NODE_ENV);
console.log("");

if (script === "congress") {
    src.congressional();
}
