// promptfoo's prompt function for the eval harness. Returns the dumped
// system/user bytes verbatim as a two-message chat array -- no trimming, no
// template interpolation, no normalisation. scripts/eval/verify-prompt-bytes.mjs
// proves this claim against the committed manifest hashes.
import { readFileSync } from "node:fs";

export default async function prompt({ vars }) {
    return [
        { role: "system", content: readFileSync(vars.system_prompt_path, "utf8") },
        { role: "user", content: readFileSync(vars.user_message_path, "utf8") },
    ];
}
