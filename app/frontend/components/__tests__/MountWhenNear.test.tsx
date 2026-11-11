import { act, cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import MountWhenNear from "app/frontend/components/MountWhenNear";

class IntersectionObserverStub {
    static instances: IntersectionObserverStub[] = [];

    readonly callback: IntersectionObserverCallback;
    readonly options: IntersectionObserverInit | undefined;
    observed: Element[] = [];
    disconnected = false;
    disconnectCount = 0;

    constructor(callback: IntersectionObserverCallback, options?: IntersectionObserverInit) {
        this.callback = callback;
        this.options = options;
        IntersectionObserverStub.instances.push(this);
    }

    observe(element: Element) {
        this.observed.push(element);
    }

    unobserve() {}

    disconnect() {
        this.disconnected = true;
        this.disconnectCount += 1;
    }

    takeRecords(): IntersectionObserverEntry[] {
        return [];
    }

    intersect() {
        act(() => {
            this.callback(
                [{ isIntersecting: true } as IntersectionObserverEntry],
                this as unknown as IntersectionObserver,
            );
        });
    }
}

const stubObserver = () => {
    IntersectionObserverStub.instances = [];
    vi.stubGlobal("IntersectionObserver", IntersectionObserverStub);
};

afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    IntersectionObserverStub.instances = [];
});

describe("MountWhenNear", () => {
    it("holds a placeholder until the observer reports the element near the viewport", () => {
        stubObserver();

        const { getByTestId, queryByTestId, queryByText } = render(
            <MountWhenNear>
                <p>below the fold</p>
            </MountWhenNear>,
        );

        expect(getByTestId("mount-when-near-placeholder")).not.toBeNull();
        expect(queryByText("below the fold")).toBeNull();

        const observer = IntersectionObserverStub.instances[0];
        expect(observer.options?.rootMargin).toBe("800px 0px");
        expect(observer.observed).toHaveLength(1);

        observer.intersect();

        expect(queryByText("below the fold")).not.toBeNull();
        expect(queryByTestId("mount-when-near-placeholder")).toBeNull();
        expect(observer.disconnected).toBe(true);
    });

    it("disconnects the observer exactly once when it unmounts before intersecting", () => {
        stubObserver();

        const { getByTestId, unmount } = render(
            <MountWhenNear>
                <p>never reached</p>
            </MountWhenNear>,
        );

        expect(getByTestId("mount-when-near-placeholder")).not.toBeNull();

        const observer = IntersectionObserverStub.instances[0];
        expect(observer.disconnectCount).toBe(0);

        unmount();

        expect(observer.disconnectCount).toBe(1);
    });

    it("renders its children on the first commit when IntersectionObserver is absent", () => {
        vi.stubGlobal("IntersectionObserver", undefined);

        const { queryByTestId, queryByText } = render(
            <MountWhenNear>
                <p>always mounted</p>
            </MountWhenNear>,
        );

        expect(queryByText("always mounted")).not.toBeNull();
        expect(queryByTestId("mount-when-near-placeholder")).toBeNull();
    });
});
