#!/usr/bin/env node
// Proves the one claim the promptfoo documentation research could not
// confirm: that a prompt function's return value reaches the provider
// byte-for-byte, with no template interpolation. If this were ever false,
// every parity guarantee this phase rests on is void, so it is proven here
// rather than assumed. Run from the repo root, matching how
// `pnpm eval:promptfoo eval -c scripts/eval/promptfooconfig.yaml` runs.
import { readFileSync } from "node:fs";
import prompt from "./prompt.mjs";

const CONFIG_PATH = new URL("./promptfooconfig.yaml", import.meta.url);

// A hand-rolled two-key extractor, not a YAML dependency: neither js-yaml
// nor any other YAML package is a declared devDependency reachable from
// scripts/ under pnpm's strict node_modules layout, and adding one just for
// two flat scalar keys would be a hidden dependency for a narrow read. This
// reads the SAME config promptfoo itself loads, so the two cannot drift.
function extractTracerCaseVars(configText) {
    const systemMatch = configText.match(/system_prompt_path:\s*(\S+)/);
    const userMatch = configText.match(/user_message_path:\s*(\S+)/);

    if (!systemMatch || !userMatch) {
        console.error("could not find system_prompt_path/user_message_path in scripts/eval/promptfooconfig.yaml");
        process.exit(1);
    }

    return { system_prompt_path: systemMatch[1], user_message_path: userMatch[1] };
}

function firstDivergingByteOffset(a, b) {
    const shorterLength = Math.min(a.length, b.length);
    for (let i = 0; i < shorterLength; i++) {
        if (a[i] !== b[i]) return i;
    }
    return a.length === b.length ? -1 : shorterLength;
}

const vars = extractTracerCaseVars(readFileSync(CONFIG_PATH, "utf8"));

// Read the dumped bytes directly, bypassing prompt.mjs, so a bug in
// prompt.mjs itself cannot make this check pass by comparing a value
// against itself.
const expectedSystemPrompt = readFileSync(vars.system_prompt_path, "utf8");
const expectedUserMessage = readFileSync(vars.user_message_path, "utf8");

const messages = await prompt({ vars });
const [systemMessage, userMessage] = messages;

let failed = false;

if (systemMessage.content !== expectedSystemPrompt) {
    const offset = firstDivergingByteOffset(systemMessage.content, expectedSystemPrompt);
    console.error(`system prompt diverged from the dumped file at byte offset ${offset}`);
    failed = true;
}

if (userMessage.content !== expectedUserMessage) {
    const offset = firstDivergingByteOffset(userMessage.content, expectedUserMessage);
    console.error(`user message diverged from the dumped file at byte offset ${offset}`);
    failed = true;
}

if (failed) {
    process.exit(1);
}

console.log(
    `prompt.mjs returns the dumped bytes unchanged (system: ${expectedSystemPrompt.length} chars, user: ${expectedUserMessage.length} chars)`,
);
