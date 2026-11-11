import { existsSync, readFileSync } from "fs";
import { join } from "path";

// @lat: [[mobile-xcode-node-binary-pin#Why ios/.xcode.env.local must not pin a full node path]]
const iosDir = join(__dirname, "..", "ios");
const localEnv = join(iosDir, ".xcode.env.local");

// @lat: [[mobile-xcode-node-binary-pin#Why ios/.xcode.env.local must not pin a full node path]]
const PINNED_INSTALL = /NODE_BINARY=["']?\/\S*\/(installs|versions)\/node\/\d+\.\d+\.\d+/;

const describeWhenPresent = existsSync(localEnv) ? describe : describe.skip;

describeWhenPresent("ios/.xcode.env.local", () => {
    const contents = existsSync(localEnv) ? readFileSync(localEnv, "utf8") : "";

    it("pins no node version", () => {
        expect(contents).not.toMatch(PINNED_INSTALL);
    });

    it("still sets NODE_BINARY, or Xcode falls back to a deprecated search", () => {
        expect(contents).toMatch(/export NODE_BINARY=/);
    });
});
