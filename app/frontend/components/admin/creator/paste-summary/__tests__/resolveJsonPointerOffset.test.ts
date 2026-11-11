import { describe, expect, it } from "vitest";
import { resolveJsonPointerOffset } from "app/frontend/components/admin/creator/paste-summary/resolveJsonPointerOffset";

describe("resolveJsonPointerOffset", () => {
    it("returns the offset of the matching key for a top-level pointer", () => {
        const json = '{"summary_markdown":"hi"}';
        expect(resolveJsonPointerOffset(json, "/summary_markdown")).toBe(json.indexOf('"summary_markdown"'));
    });

    it("returns null when the JSON cannot be parsed", () => {
        expect(resolveJsonPointerOffset("{not json", "/anything")).toBeNull();
    });

    it("returns null when the pointer references a missing key", () => {
        expect(resolveJsonPointerOffset('{"a":1}', "/b")).toBeNull();
    });

    it("resolves an array-index pointer to the parent key offset", () => {
        const json = '{"draft_org_positions":[{"stance":"support"}]}';
        expect(resolveJsonPointerOffset(json, "/draft_org_positions/0")).toBe(json.indexOf('"draft_org_positions"'));
    });

    it("returns null when the array index is out of bounds", () => {
        expect(resolveJsonPointerOffset('{"xs":[]}', "/xs/0")).toBeNull();
    });

    it("decodes JSONPointer escapes (~1 → /)", () => {
        const json = '{"a/b":1}';
        expect(resolveJsonPointerOffset(json, "/a~1b")).toBe(json.indexOf('"a/b"'));
    });

    it("decodes JSONPointer escapes (~0 → ~)", () => {
        const json = '{"a~b":1}';
        expect(resolveJsonPointerOffset(json, "/a~0b")).toBe(json.indexOf('"a~b"'));
    });

    // In a JSON Pointer (RFC 6901), `~1` is turned back into `/` before `~0` is
    // turned back into `~`. So a key that really contains "~1" has to be
    // written "~01": writing "~1" would just decode to "/".
    it("decodes ~01 to the literal ~1 (escape ordering)", () => {
        const json = '{"~1":1}';
        expect(resolveJsonPointerOffset(json, "/~01")).toBe(json.indexOf('"~1"'));
    });

    it("walks a nested object path and anchors on the leaf key", () => {
        const json = '{"summary":{"sections":[{"title":"hi"}]}}';
        expect(resolveJsonPointerOffset(json, "/summary/sections/0/title")).toBe(json.indexOf('"title"'));
    });

    // A key that looks like a number but belongs to an object must not be
    // treated as an array index. The final lookup decides by what the parent
    // actually is, not by whether the path segment looks numeric.
    it("treats a numeric-string object key as a key, not an array index", () => {
        const json = '{"0":{"stance":"support"}}';
        expect(resolveJsonPointerOffset(json, "/0")).toBe(json.indexOf('"0"'));
    });
});
