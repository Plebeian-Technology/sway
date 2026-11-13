import { spawnSync } from "child_process";
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

const repoRoot = join(__dirname, "..", "..");

describe("mobile/scripts/run-ios.sh", () => {
    let root: string;
    let binDir: string;

    const copy = (path: string) => {
        mkdirSync(join(root, path, ".."), { recursive: true });
        copyFileSync(join(repoRoot, path), join(root, path));
    };

    beforeEach(() => {
        root = mkdtempSync(join(tmpdir(), "run-ios-"));
        ["mobile/scripts/run-ios.sh", "mobile/scripts/with-vault-env.sh", "mobile/scripts/xcode-node-env.sh"].forEach(
            copy,
        );
        copy("deploy/config/load.sh");
        mkdirSync(join(root, "lib"));
        writeFileSync(join(root, "lib", "sway_deploy_config.rb"), "");
        writeFileSync(join(root, "mobile", ".env.local"), "APPLE_BUNDLE_ID=app.example.test\n");

        binDir = join(root, "bin");
        mkdirSync(binDir);
        writeFileSync(
            join(binDir, "expo"),
            '#!/bin/sh\nprintf "%s|%s|%s" "$EXPO_PUBLIC_API_URL" "$EXPO_PUBLIC_DEV_TUNNEL_HOST" "$*"\n',
        );
        chmodSync(join(binDir, "expo"), 0o755);
    });

    afterEach(() => {
        rmSync(root, { recursive: true, force: true });
    });

    const run = (overrides: Record<string, string> = {}) =>
        spawnSync("bash", [join(root, "mobile", "scripts", "run-ios.sh"), "--device", "x"], {
            env: { NODE_ENV: "test", PATH: `${binDir}:${process.env.PATH}`, HOME: process.env.HOME, ...overrides },
            encoding: "utf8",
        });

    // @lat: [[mobile-expo-config#Deployment identifiers come from the environment#The simulator build uses the dev tunnel when one is configured]]
    it("points the app at the dev tunnel named in deploy/config/sway.env", () => {
        writeFileSync(join(root, "deploy", "config", "sway.env"), "DEV_TUNNEL_HOST=tunnel.example.test\n");

        const result = run();

        expect(result.status).toBe(0);
        expect(result.stdout).toBe("https://tunnel.example.test|tunnel.example.test|run:ios --device x");
    });

    it("falls back to localhost, and says so, without a tunnel", () => {
        const result = run();

        expect(result.stdout).toBe("https://localhost:3333||run:ios --device x");
        expect(result.stderr).toMatch(/no DEV_TUNNEL_HOST/);
    });

    it("lets an exported tunnel host and API address win", () => {
        writeFileSync(join(root, "deploy", "config", "sway.env"), "DEV_TUNNEL_HOST=tunnel.example.test\n");

        const result = run({
            EXPO_PUBLIC_DEV_TUNNEL_HOST: "other.example.test",
            EXPO_PUBLIC_API_URL: "https://api.example.test",
        });

        expect(result.stdout).toBe("https://api.example.test|other.example.test|run:ios --device x");
    });
});
