import { describe, expect, it } from "vitest";
import { devWatchIgnore } from "../../../vite/devWatchIgnore";

// @lat: [[dev-server-watching#Why the ignore rule is tested in both directions]]

const ROOT = "/app";
const ignored = devWatchIgnore(ROOT);

describe("devWatchIgnore", () => {
    describe("ignores what a machine writes", () => {
        it.each([
            ["the coverage report the test suite writes", "/app/coverage/index.html"],
            ["a coverage report inside an agent's worktree", "/app/.claude/worktrees/some-task/coverage/index.html"],
            ["anything else under .claude", "/app/.claude/settings.json"],
            ["agent skills and worktrees under .agents", "/app/.agents/skills/lat-md/SKILL.md"],
            [
                "a file inside .worktrees",
                "/app/.worktrees/some-branch/spec/factories/push_notification_subscription.rb",
            ],
            ["the pnpm content-addressable store", "/app/.pnpm-store/v3/files/00/deadbeef"],
            [
                "legislation pipeline artifacts",
                "/app/legislation/law/congress-congress-united_states/code/title_3/301.md",
            ],
            ["the git directory", "/app/.git/index"],
            ["the databases", "/app/storage/test.sqlite3"],
            ["the logs", "/app/log/development.log"],
            ["scratch files", "/app/tmp/pids/server.pid"],
            ["the issue tracker", "/app/.beads/backup/backup_state.json"],
            ["the phone app", "/app/mobile/ios/build/index.html"],
            ["installed packages", "/app/node_modules/vite/dist/client/client.mjs"],
        ])("ignores %s", (_name, path) => {
            expect(ignored(path)).toBe(true);
        });

        it.each([
            ["a coverage report in a worktree kept outside .claude", "/app/worktrees/some-agent/coverage/index.html"],
            ["a package folder sitting under source", "/app/app/frontend/node_modules/some-package/index.js"],
        ])("ignores %s", (_name, path) => {
            expect(ignored(path)).toBe(true);
        });
    });

    describe("keeps watching source", () => {
        it.each([
            [
                "a Rails template — the reload this project sends on purpose",
                "/app/app/views/layouts/application.html.erb",
            ],
            ["a Rails helper", "/app/app/helpers/application_helper.rb"],
            ["a React page", "/app/app/frontend/pages/admin/LlmSettings.tsx"],
            ["the Rails error pages, which are real pages", "/app/public/404.html"],
            ["the dev server's own config", "/app/vite.config.ts"],
        ])("watches %s", (_name, path) => {
            expect(ignored(path)).toBe(false);
        });

        it("watches a file outside the project", () => {
            expect(ignored("/elsewhere/.env.local")).toBe(false);
        });

        it("watches the project folder itself", () => {
            expect(ignored(ROOT)).toBe(false);
        });
    });

    it("ignores the folder, so nothing inside it is ever opened", () => {
        expect(ignored("/app/coverage")).toBe(true);
        expect(ignored("/app/.claude")).toBe(true);
        expect(ignored("/app/.worktrees")).toBe(true);
    });
});
