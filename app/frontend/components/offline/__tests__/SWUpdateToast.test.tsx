import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactElement } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

const toastMock = vi.fn<(...args: unknown[]) => string>(() => "sw-update-toast");
const dismissMock = vi.fn<(id?: string) => void>();

vi.mock("react-hot-toast", () => ({
    default: Object.assign((...args: unknown[]) => toastMock(...args), {
        dismiss: (id?: string) => dismissMock(id),
    }),
}));

const useRegisterSWMock = vi.fn<(options?: { onNeedReload?: () => void }) => Record<string, unknown>>();
vi.mock("virtual:pwa-register/react", () => ({
    useRegisterSW: (options: { onNeedReload?: () => void }) => useRegisterSWMock(options),
}));

vi.mock("app/frontend/sway_utils/offlineTelemetry", () => ({ trackOfflineEvent: vi.fn<(name: string) => void>() }));

import { preserveOpenPageOnWorkerUpdate } from "app/frontend/service-worker/registerSW";
import SWUpdateToast from "app/frontend/components/offline/SWUpdateToast";

afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    toastMock.mockClear();
    dismissMock.mockClear();
    useRegisterSWMock.mockReset();
});

const updateAvailable = (updateServiceWorker = vi.fn<(reload?: boolean) => Promise<void>>(() => Promise.resolve())) =>
    useRegisterSWMock.mockReturnValue({
        needRefresh: [true, vi.fn<(v: boolean) => void>()],
        offlineReady: [false, vi.fn<(v: boolean) => void>()],
        updateServiceWorker,
    });

describe("SWUpdateToast — the update prompt takes the Toaster's corner", () => {
    // @lat: [[toasts#Toast position is owned by the mounted Toaster]]
    it("names no position of its own", () => {
        updateAvailable();
        render(<SWUpdateToast />);

        expect(toastMock).toHaveBeenCalledTimes(1);
        expect(toastMock.mock.calls[0][1]).not.toHaveProperty("position");
    });

    // @lat: [[client-caches-and-identity#Static worker lifecycle]]
    it("overrides the plugin's automatic reload when the worker takes control", () => {
        updateAvailable();
        render(<SWUpdateToast />);
        expect(useRegisterSWMock).toHaveBeenCalledWith({ onNeedReload: preserveOpenPageOnWorkerUpdate });
    });

    it("still waits to be answered rather than fading", () => {
        updateAvailable();
        render(<SWUpdateToast />);

        expect(toastMock.mock.calls[0][1]).toMatchObject({ duration: Infinity });
    });

    it("reloads only after the reader clicks Reload and the update request resolves", async () => {
        let finish!: () => void;
        const update = vi.fn<(reload?: boolean) => Promise<void>>(
            () =>
                new Promise<void>((resolve) => {
                    finish = resolve;
                }),
        );
        updateAvailable(update);
        render(<SWUpdateToast />);
        const content = toastMock.mock.calls[0][0] as (toast: { id: string }) => ReactElement;
        render(content({ id: "update" }));
        const reload = vi.fn<() => void>();
        vi.stubGlobal(
            "window",
            new Proxy(window, { get: (target, key) => (key === "location" ? { reload } : Reflect.get(target, key)) }),
        );

        fireEvent.click(screen.getByRole("button", { name: "Reload" }));
        expect(update).toHaveBeenCalledWith(false);
        expect(reload).not.toHaveBeenCalled();
        finish();
        await waitFor(() => expect(reload).toHaveBeenCalledTimes(1));
    });

    it("does not reload if the update request fails", async () => {
        const error = new Error("Update unavailable");
        const update = vi.fn<(reload?: boolean) => Promise<void>>().mockRejectedValue(error);
        const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
        updateAvailable(update);
        render(<SWUpdateToast />);
        const content = toastMock.mock.calls[0][0] as (toast: { id: string }) => ReactElement;
        render(content({ id: "update" }));
        const reload = vi.fn<() => void>();
        vi.stubGlobal(
            "window",
            new Proxy(window, { get: (target, key) => (key === "location" ? { reload } : Reflect.get(target, key)) }),
        );

        fireEvent.click(screen.getByRole("button", { name: "Reload" }));
        await waitFor(() => expect(log).toHaveBeenCalledWith(error));
        expect(reload).not.toHaveBeenCalled();
    });
});
