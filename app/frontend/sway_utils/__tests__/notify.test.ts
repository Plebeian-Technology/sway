import { beforeEach, describe, expect, it, vi } from "vitest";

const successMock = vi.fn<(message: unknown, options: Record<string, unknown>) => string>();
const errorMock = vi.fn<(message: unknown, options: Record<string, unknown>) => string>();
const plainMock = vi.fn<(message: unknown, options: Record<string, unknown>) => string>();
const dismissMock = vi.fn<(id?: string) => void>();

vi.mock("react-hot-toast", () => {
    const toastFn = (message: unknown, options: Record<string, unknown>) => plainMock(message, options);
    toastFn.success = (message: unknown, options: Record<string, unknown>) => successMock(message, options);
    toastFn.error = (message: unknown, options: Record<string, unknown>) => errorMock(message, options);
    toastFn.dismiss = (id?: string) => dismissMock(id);
    return { default: toastFn };
});

let idCounter = 0;

const freshNotify = async () => {
    vi.resetModules();
    const { notify } = await import("app/frontend/sway_utils");
    return notify;
};

beforeEach(() => {
    idCounter = 0;
    successMock.mockReset();
    errorMock.mockReset();
    plainMock.mockReset();
    dismissMock.mockReset();

    const resolveId = (_message: unknown, options: Record<string, unknown>) =>
        (options?.id as string | undefined) || `generated-${idCounter++}`;
    successMock.mockImplementation(resolveId);
    errorMock.mockImplementation(resolveId);
    plainMock.mockImplementation(resolveId);
});

describe("notify position", () => {
    it("does not force a position when the caller does not pass one", async () => {
        const notify = await freshNotify();
        notify({ level: "success", title: "Saved." });
        expect(successMock.mock.calls[0][1].position).toBeUndefined();
    });

    it("forwards an explicit position when the caller passes one", async () => {
        const notify = await freshNotify();
        notify({ level: "success", title: "Saved.", position: "bottom-left" });
        expect(successMock.mock.calls[0][1].position).toBe("bottom-left");
    });
});

describe("notify visible-toast cap", () => {
    it("does not evict at five or fewer visible toasts", async () => {
        const notify = await freshNotify();
        for (let i = 0; i < 5; i++) {
            notify({ level: "success", title: `Toast ${i}` });
        }
        expect(dismissMock).not.toHaveBeenCalled();
    });

    it("evicts exactly the oldest toast once a sixth arrives", async () => {
        const notify = await freshNotify();
        const ids = [0, 1, 2, 3, 4, 5].map((i) => notify({ level: "success", title: `Toast ${i}` }));
        expect(dismissMock).toHaveBeenCalledTimes(1);
        expect(dismissMock).toHaveBeenCalledWith(ids[0]);
    });

    it("evicts oldest-first across repeated overflow", async () => {
        const notify = await freshNotify();
        const ids = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => notify({ level: "success", title: `Toast ${i}` }));
        expect(dismissMock.mock.calls.map((call) => call[0])).toEqual([ids[0], ids[1], ids[2]]);
    });

    it("does not consume a second slot or trigger eviction when a message de-duplicates", async () => {
        const notify = await freshNotify();
        notify({ level: "success", title: "Repeat" });
        notify({ level: "success", title: "A" });
        notify({ level: "success", title: "B" });
        notify({ level: "success", title: "C" });
        notify({ level: "success", title: "D" });
        notify({ level: "success", title: "Repeat" });
        expect(dismissMock).not.toHaveBeenCalled();
    });

    it("still evicts the true oldest once a genuinely new toast follows a de-duplicated repeat", async () => {
        const notify = await freshNotify();
        const firstId = notify({ level: "success", title: "Repeat" });
        notify({ level: "success", title: "A" });
        notify({ level: "success", title: "B" });
        notify({ level: "success", title: "C" });
        notify({ level: "success", title: "D" });
        notify({ level: "success", title: "Repeat" });
        notify({ level: "success", title: "E" });
        expect(dismissMock).toHaveBeenCalledTimes(1);
        expect(dismissMock).toHaveBeenCalledWith(firstId);
    });
});
