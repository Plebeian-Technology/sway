let mockFocused = true;

jest.mock("@react-navigation/native", () => {
    const ReactMod = jest.requireActual<typeof import("react")>("react");
    return {
        useFocusEffect: (cb: () => undefined | (() => void)) => {
            const focused = mockFocused;
            ReactMod.useEffect(() => (focused ? cb() : undefined), [cb, focused]);
        },
    };
});

import { renderHook } from "@testing-library/react-native";

import { usePolling } from "../../../src/hooks/admin/usePolling";

// @lat: [[mobile-bill-creator#Sections#The pipeline progress section#Polling while a run is in flight]]
describe("usePolling", () => {
    beforeEach(() => {
        mockFocused = true;
        jest.useFakeTimers();
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    it("calls refresh every interval while active", () => {
        const refresh = jest.fn();
        renderHook(() => usePolling(refresh, true, 5000));

        expect(refresh).not.toHaveBeenCalled();
        jest.advanceTimersByTime(5000);
        expect(refresh).toHaveBeenCalledTimes(1);
        jest.advanceTimersByTime(10000);
        expect(refresh).toHaveBeenCalledTimes(3);
    });

    it("does not call refresh while inactive", () => {
        const refresh = jest.fn();
        renderHook(() => usePolling(refresh, false, 5000));

        jest.advanceTimersByTime(20000);
        expect(refresh).not.toHaveBeenCalled();
    });

    it("stops when it becomes inactive", () => {
        const refresh = jest.fn();
        const { rerender } = renderHook(({ active }: { active: boolean }) => usePolling(refresh, active, 5000), {
            initialProps: { active: true },
        });

        jest.advanceTimersByTime(5000);
        rerender({ active: false });
        jest.advanceTimersByTime(20000);
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    it("stops on unmount", () => {
        const refresh = jest.fn();
        const { unmount } = renderHook(() => usePolling(refresh, true, 5000));

        unmount();
        jest.advanceTimersByTime(20000);
        expect(refresh).not.toHaveBeenCalled();
    });

    it("stops when the screen loses focus", () => {
        const refresh = jest.fn();
        const { rerender } = renderHook(() => usePolling(refresh, true, 5000));

        mockFocused = false;
        rerender({});
        jest.advanceTimersByTime(20000);
        expect(refresh).not.toHaveBeenCalled();
    });
});
