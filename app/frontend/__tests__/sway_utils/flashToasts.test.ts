import { beforeEach, describe, expect, it, vi } from "vitest";

const { onMock } = vi.hoisted(() => ({ onMock: vi.fn<(event: string, callback: (e: unknown) => void) => void>() }));
vi.mock("@inertiajs/react", () => ({ router: { on: onMock } }));

const notifyMock = vi.fn<(...args: unknown[]) => string>();
vi.mock("app/frontend/sway_utils", () => ({ notify: (...args: unknown[]) => notifyMock(...args) }));

import { registerFlashToasts } from "app/frontend/sway_utils/flashToasts";

const fireSuccess = (flash: { id?: string; notice?: string; alert?: string } | undefined) => {
    const handler = onMock.mock.calls.at(-1)?.[1] as (event: unknown) => void;
    handler({ detail: { page: { props: { flash } } } });
};

describe("registerFlashToasts", () => {
    beforeEach(() => {
        onMock.mockClear();
        notifyMock.mockClear();
    });

    it("subscribes to the Inertia success event", () => {
        registerFlashToasts();
        expect(onMock).toHaveBeenCalledWith("success", expect.any(Function));
    });

    it("toasts flash.notice as a success toast", () => {
        registerFlashToasts();
        fireSuccess({ notice: "Saved." });
        expect(notifyMock).toHaveBeenCalledWith(expect.objectContaining({ level: "success", title: "Saved." }));
    });

    it("toasts flash.alert as an error toast", () => {
        registerFlashToasts();
        fireSuccess({ alert: "Something went wrong." });
        expect(notifyMock).toHaveBeenCalledWith(
            expect.objectContaining({ level: "error", title: "Something went wrong." }),
        );
    });

    it("does not toast when the visit carries no flash", () => {
        registerFlashToasts();
        fireSuccess(undefined);
        expect(notifyMock).not.toHaveBeenCalled();
    });

    it("does not re-toast the same flash id, replayed by a partial reload", () => {
        registerFlashToasts();
        fireSuccess({ id: "req-1", notice: "Saved." });
        fireSuccess({ id: "req-1", notice: "Saved." });
        expect(notifyMock).toHaveBeenCalledTimes(1);
    });

    it("toasts two identical notices from two requests, which carry different ids", () => {
        registerFlashToasts();
        fireSuccess({ id: "req-1", notice: "Category added." });
        fireSuccess({ id: "req-2", notice: "Category added." });
        expect(notifyMock).toHaveBeenCalledTimes(2);
    });

    it("does not re-toast the same alert id either", () => {
        registerFlashToasts();
        fireSuccess({ id: "req-1", alert: "That name is taken." });
        fireSuccess({ id: "req-1", alert: "That name is taken." });
        expect(notifyMock).toHaveBeenCalledTimes(1);
    });

    it("falls back to the message text when a flash carries no id", () => {
        registerFlashToasts();
        fireSuccess({ notice: "Saved." });
        fireSuccess({ notice: "Saved." });
        expect(notifyMock).toHaveBeenCalledTimes(1);
    });

    it("toasts the same message again once the flash has cleared and returned", () => {
        registerFlashToasts();
        fireSuccess({ notice: "Saved." });
        fireSuccess(undefined);
        fireSuccess({ notice: "Saved." });
        expect(notifyMock).toHaveBeenCalledTimes(2);
    });

    it("does not force a position on the success toast, so the mounted Toaster's position wins", () => {
        registerFlashToasts();
        fireSuccess({ notice: "Saved." });
        expect(notifyMock.mock.calls[0][0]).not.toHaveProperty("position");
    });

    it("does not force a position on the error toast, so the mounted Toaster's position wins", () => {
        registerFlashToasts();
        fireSuccess({ alert: "Something went wrong." });
        expect(notifyMock.mock.calls[0][0]).not.toHaveProperty("position");
    });
});
