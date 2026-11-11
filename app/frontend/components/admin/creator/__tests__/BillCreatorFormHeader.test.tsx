// "Don't Save + Reset to New" must visit with no query string — it used to sweep the
// whole query forward, including a pinned ?run_id= or ?cursor= that must never carry over.

import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

const { routerGetMock } = vi.hoisted(() => ({ routerGetMock: vi.fn<(url: string, options?: unknown) => void>() }));
vi.mock("@inertiajs/react", () => ({
    router: { get: routerGetMock },
}));

import BillCreatorFormHeader from "app/frontend/components/admin/creator/BillCreatorFormHeader";
import type { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { ROUTES } from "app/frontend/sway_constants";

// Only the two methods this component actually calls on `storage`.
const removeMock = vi.fn<() => void>();
const storage = { name: () => "bill", remove: removeMock } as unknown as TempBillStorage;

afterEach(() => {
    cleanup();
    routerGetMock.mockClear();
    removeMock.mockClear();
});

describe("BillCreatorFormHeader — Don't Save + Reset to New", () => {
    it("visits the empty picker with no query string, carrying nothing forward", async () => {
        const originalLocation = window.location.href;
        window.history.pushState({}, "", "/admin/bill_creator/42/pipeline_llm?run_id=7&cursor=99");

        render(<BillCreatorFormHeader storage={storage} />);
        await userEvent.click(screen.getByText("Don't Save + Reset to New"));

        expect(routerGetMock).toHaveBeenCalledExactlyOnceWith(ROUTES.billCreator);

        window.history.pushState({}, "", originalLocation);
    });
});
