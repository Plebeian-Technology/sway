import { spawnSync } from "child_process";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

const repoRoot = join(__dirname, "..", "..");

const runnerEnv = (overrides: Record<string, string> = {}): NodeJS.ProcessEnv => ({
    NODE_ENV: "test",
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    ...overrides,
});

describe("mobile/scripts/with-vault-env.sh", () => {
    let root: string;
    let runner: string;
    let envFile: string;

    beforeEach(() => {
        root = mkdtempSync(join(tmpdir(), "with-vault-env-"));
        mkdirSync(join(root, "mobile", "scripts"), { recursive: true });
        mkdirSync(join(root, "scripts", "lib"), { recursive: true });
        runner = join(root, "mobile", "scripts", "with-vault-env.sh");
        copyFileSync(join(repoRoot, "mobile", "scripts", "with-vault-env.sh"), runner);
        copyFileSync(join(repoRoot, "scripts", "lib", "secrets.sh"), join(root, "scripts", "lib", "secrets.sh"));
        envFile = join(root, "mobile", ".env.local");
    });

    afterEach(() => {
        rmSync(root, { recursive: true, force: true });
    });

    const run = (env: NodeJS.ProcessEnv, ...names: string[]) =>
        spawnSync("bash", [runner, ...names, "--", "sh", "-c", 'printf "%s|%s" "$APPLE_BUNDLE_ID" "$EAS_PROJECT_ID"'], {
            env,
            encoding: "utf8",
        });

    // @lat: [[mobile-expo-config#Deployment identifiers come from the environment#Local values come from mobile/.env.local]]
    it("takes a requested name from mobile/.env.local without asking the secret store", () => {
        writeFileSync(
            envFile,
            '# local\nexport APPLE_BUNDLE_ID="app.example.local"\nEAS_PROJECT_ID=not-requested\nEXPO_PUBLIC_API_URL=https://x\n',
        );

        const result = run(runnerEnv(), "APPLE_BUNDLE_ID");

        expect(result.status).toBe(0);
        expect(result.stdout).toBe("app.example.local|");
    });

    it("lets an exported value win over mobile/.env.local", () => {
        writeFileSync(envFile, "APPLE_BUNDLE_ID=app.example.local\n");

        const result = run(runnerEnv({ APPLE_BUNDLE_ID: "app.example.exported" }), "APPLE_BUNDLE_ID");

        expect(result.stdout).toBe("app.example.exported|");
    });

    it("still turns to the secret store for a name mobile/.env.local lacks", () => {
        writeFileSync(envFile, "APPLE_BUNDLE_ID=app.example.local\n");

        const result = run(runnerEnv(), "APPLE_BUNDLE_ID", "EAS_PROJECT_ID");

        expect(result.status).toBe(1);
        expect(result.stderr).toMatch(/EAS_PROJECT_ID unset.*SWAY_SECRETS_ACCOUNT/);
        expect(result.stderr).not.toMatch(/APPLE_BUNDLE_ID unset/);
    });
});
