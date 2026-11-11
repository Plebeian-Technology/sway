import { describe, expect, it } from "vitest";
import { uniqueStableKeys } from "app/frontend/sway_utils/uniqueStableKeys";

// @lat: [[unique-stable-keys-collision-bug#Why uniqueStableKeys' counter could collide with a real key]]
describe("uniqueStableKeys", () => {
    const isUnique = (keys: string[]) => new Set(keys).size === keys.length;

    it("returns one key per identity, in order", () => {
        expect(uniqueStableKeys(["a", "b", "c"])).toHaveLength(3);
    });

    it("gives distinct identities distinct keys", () => {
        expect(isUnique(uniqueStableKeys(["a", "b", "c"]))).toBe(true);
    });

    it("gives repeated identities distinct keys", () => {
        expect(isUnique(uniqueStableKeys(["a", "a", "a"]))).toBe(true);
    });

    // The bug itself. A repeated "A" produces "A#1", and the third entry's own
    // name IS "A#1", so both end up with the same key.
    it("does not collide a repeat's suffix with an identity that looks like one", () => {
        expect(isUnique(uniqueStableKeys(["A", "A", "A#1"]))).toBe(true);
    });

    it("does not collide in the other order either", () => {
        expect(isUnique(uniqueStableKeys(["A#1", "A", "A"]))).toBe(true);
    });

    // The digit does not matter: any name ending in #<number> is the same trap.
    it.each([
        [["Ward 5 Coalition", "Ward 5 Coalition", "Ward 5 Coalition#1"]],
        [["x", "x", "x", "x#1", "x#2"]],
        [["", "", "#1"]],
    ])("keeps %s unique", (identities: string[]) => {
        expect(isUnique(uniqueStableKeys(identities))).toBe(true);
    });

    // The guarantee this helper was written for, still holding: a key must not
    // change when a NEIGHBOUR is removed, because that rebuilds the card and
    // throws away the operator's unsaved edit.
    it("does not move an entry's key when a different identity is removed", () => {
        const before = uniqueStableKeys(["a", "b", "c"]);
        const after = uniqueStableKeys(["a", "c"]);

        expect(after[0]).toBe(before[0]);
        expect(after[1]).toBe(before[2]);
    });

    it("does not move an earlier twin's key when a later twin is removed", () => {
        const before = uniqueStableKeys(["a", "a", "b"]);
        const after = uniqueStableKeys(["a", "b"]);

        expect(after[0]).toBe(before[0]);
        expect(after[1]).toBe(before[2]);
    });
});
