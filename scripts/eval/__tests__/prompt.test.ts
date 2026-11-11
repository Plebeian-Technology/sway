import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import prompt from "../prompt.mjs";

// @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the payload is built through Llm::PromptPayload, not call]]
describe("prompt.mjs", () => {
    let dir: string;

    afterEach(() => {
        if (dir) rmSync(dir, { recursive: true, force: true });
    });

    it("returns the dumped bytes byte-identically, with no trimming or template interpolation", async () => {
        dir = mkdtempSync(join(tmpdir(), "prompt-mjs-spec-"));
        const systemPath = join(dir, "system_prompt.txt");
        const userPath = join(dir, "user_message.txt");

        const systemContent = "  \n leading and trailing whitespace preserved \n  ";
        const userContent = "contains a template-looking substring {{ var }} that must not interpolate\n\ttab preserved";

        writeFileSync(systemPath, systemContent);
        writeFileSync(userPath, userContent);

        const messages = await prompt({
            vars: { system_prompt_path: systemPath, user_message_path: userPath },
        });

        expect(messages).toEqual([
            { role: "system", content: systemContent },
            { role: "user", content: userContent },
        ]);
    });
});
