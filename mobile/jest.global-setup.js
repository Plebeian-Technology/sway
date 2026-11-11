const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");

// @lat: [[toolchain-pins#Toolchain pins#Why the frontend suite refuses to start under the wrong Node]]
module.exports = function assertPinnedNode(globalConfig) {
    const pinned = readFileSync(resolve(globalConfig.rootDir, ".node-version"), "utf8").trim().replace(/^v/, "");
    const running = process.version.replace(/^v/, "");

    if (running === pinned) return;

    throw new Error(
        [
            "",
            "The mobile suite is running under the wrong Node.",
            "",
            `  pinned  ${pinned}   (mobile/.node-version)`,
            `  running ${running}   (${process.execPath})`,
            "",
            "Failures under an unpinned Node look like application defects and are not.",
            "Run through the pinned version — `mise exec -- pnpm --dir mobile test` — or",
            "change mobile/.node-version if the pin itself should move.",
            "",
        ].join("\n"),
    );
};
