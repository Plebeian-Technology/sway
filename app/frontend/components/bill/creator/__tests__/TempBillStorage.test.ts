import { beforeEach, describe, expect, it, vi } from "vitest";
import { notify, SWAY_STORAGE } from "app/frontend/sway_utils";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";

vi.mock("app/frontend/sway_utils", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_utils")>();
    return { ...actual, notify: vi.fn<(args: Record<string, unknown>) => void>() };
});

const CANONICAL_BILL = SWAY_STORAGE.Local.BillCreator.Bill;
const CANONICAL_ORGS = SWAY_STORAGE.Local.BillCreator.Organizations;
const CANONICAL_VOTES = SWAY_STORAGE.Local.BillCreator.LegislatorVotes;

const RETIRED_BILL = "@sway/retired/temp/bill";

describe("TempBillStorage — canonical storage", () => {
    beforeEach(() => {
        localStorage.clear();
        vi.clearAllMocks();
    });

    describe("Constructor", () => {
        it("defaults to canonical Bill key when constructed without arguments", () => {
            const storage = new TempBillStorage();
            expect(storage.key).toBe(CANONICAL_BILL);
        });
    });

    describe("Direct canonical read/write", () => {
        it("writes directly to the canonical key and emits success notification", () => {
            const storage = new TempBillStorage(CANONICAL_BILL);
            storage.set({ id: 1, title: "Canonical Bill" });

            expect(localStorage.getItem(CANONICAL_BILL)).toBe(JSON.stringify({ id: 1, title: "Canonical Bill" }));
            expect(notify).toHaveBeenCalledWith(expect.objectContaining({ level: "success" }));
        });

        it("reads canonical key directly when present", () => {
            localStorage.setItem(CANONICAL_BILL, JSON.stringify({ id: 1, title: "Direct Read" }));
            const storage = new TempBillStorage(CANONICAL_BILL);
            expect(storage.peek()).toEqual({ id: 1, title: "Direct Read" });
        });
    });

    describe("Retired keys are not read", () => {
        it("returns null for a draft stored only under a retired key", () => {
            localStorage.setItem(RETIRED_BILL, JSON.stringify({ id: 42, title: "Old Draft" }));
            const storage = new TempBillStorage(CANONICAL_BILL);

            expect(storage.peek()).toBeNull();
            expect(localStorage.getItem(CANONICAL_BILL)).toBeNull();
        });
    });

    describe("Purge", () => {
        it("instance remove() clears the canonical key", () => {
            localStorage.setItem(CANONICAL_BILL, JSON.stringify({ id: 1 }));

            const storage = new TempBillStorage(CANONICAL_BILL);
            storage.remove();

            expect(localStorage.getItem(CANONICAL_BILL)).toBeNull();
            expect(notify).toHaveBeenCalledWith(expect.objectContaining({ level: "warning" }));
        });

        it("static remove() clears all three canonical keys", () => {
            [CANONICAL_BILL, CANONICAL_ORGS, CANONICAL_VOTES].forEach((k) => {
                localStorage.setItem(k, JSON.stringify({ test: true }));
            });

            TempBillStorage.remove();

            [CANONICAL_BILL, CANONICAL_ORGS, CANONICAL_VOTES].forEach((k) => {
                expect(localStorage.getItem(k)).toBeNull();
            });
        });
    });

    describe("Error resilience", () => {
        it("returns null without crashing on corrupt JSON", () => {
            localStorage.setItem(CANONICAL_BILL, "{corrupt json syntax error...");
            const storage = new TempBillStorage(CANONICAL_BILL);

            expect(storage.peek()).toBeNull();
        });
    });

    describe("name() mapping", () => {
        it("returns correct display names for canonical keys", () => {
            expect(new TempBillStorage(CANONICAL_BILL).name()).toBe("Bill");
            expect(new TempBillStorage(CANONICAL_ORGS).name()).toBe("Supporting/Opposing Arguments");
            expect(new TempBillStorage(CANONICAL_VOTES).name()).toBe("Legislator Votes");
        });
    });
});
