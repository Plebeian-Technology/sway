import { renderHook } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";

const reloadMock = vi.fn<(config?: { only?: string[] }) => void>();
vi.mock("@inertiajs/react", () => ({
    router: { reload: reloadMock },
}));

describe("useActionCableReconnect", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("calls router.reload with { only } on window online event", async () => {
        const { useActionCableReconnect } = await import("app/frontend/hooks/useActionCableReconnect");
        renderHook(() => useActionCableReconnect(["scores"]));
        window.dispatchEvent(new Event("online"));
        // No preserveScroll here: in Inertia 2 a partial reload already keeps the scroll position
        expect(reloadMock).toHaveBeenCalledWith({ only: ["scores"] });
    });

    it("removes listener on unmount", async () => {
        const { useActionCableReconnect } = await import("app/frontend/hooks/useActionCableReconnect");
        const { unmount } = renderHook(() => useActionCableReconnect(["scores"]));
        unmount();
        window.dispatchEvent(new Event("online"));
        expect(reloadMock).not.toHaveBeenCalled();
    });
});
