// The toast goes through the existing notify() helper in
// app/frontend/sway_utils, so this file swaps notify() for a stand-in and
// checks how it was called. The notistack library is NOT involved.

import { fireEvent, render } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

const notifyMock = vi.fn<(args: unknown) => void>();
vi.mock("app/frontend/sway_utils", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_utils")>();
    return {
        ...actual,
        notify: (args: unknown) => notifyMock(args),
    };
});

vi.mock("app/frontend/hooks/useSearchParams", () => ({
    useSearchParams: () => ({ entries: {}, remove: vi.fn<() => void>() }),
}));

// Stand in for @inertiajs/react, with page data each test can set
const pagePropsRef: { current: Record<string, unknown> } = { current: {} };
const routerPostMock = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", async (importOriginal) => {
    const actual = await importOriginal<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: () => ({ props: pagePropsRef.current }),
        useForm: () => ({
            data: { FOR: [], AGAINST: [], ABSTAIN: [] },
            setData: vi.fn<(key: string, value: unknown) => void>(),
            post: vi.fn<() => void>(),
            processing: false,
            errors: {},
        }),
        router: { reload: vi.fn<() => void>(), post: (...args: unknown[]) => routerPostMock(...args) },
    };
});

import BillCreatorLegislatorVotes from "app/frontend/components/admin/creator/BillCreatorLegislatorVotes";

describe("BillCreatorLegislatorVotes — refresh toast", () => {
    beforeEach(() => {
        notifyMock.mockClear();
        pagePropsRef.current = {
            // The least page data the component needs to render
            bill: { id: 1, external_id: "X" },
            legislators: [],
            legislator_votes: [],
        };
    });

    it("calls notify with the formatted message when both refresh props are present", () => {
        pagePropsRef.current = {
            ...pagePropsRef.current,
            legislator_votes_refreshed_at: "09:01",
            legislator_votes_source: "legistar",
        };
        render(<BillCreatorLegislatorVotes />);
        expect(notifyMock).toHaveBeenCalledWith(
            expect.objectContaining({
                level: "info",
                title: "Legislator votes refreshed at 09:01 from legistar.",
            }),
        );
    });

    it("does NOT call notify when refreshed_at is null", () => {
        pagePropsRef.current = {
            ...pagePropsRef.current,
            legislator_votes_refreshed_at: null,
            legislator_votes_source: "legistar",
        };
        render(<BillCreatorLegislatorVotes />);
        expect(notifyMock).not.toHaveBeenCalledWith(
            expect.objectContaining({
                title: expect.stringContaining("Legislator votes refreshed"),
            }),
        );
    });

    it("does NOT call notify when both props are undefined", () => {
        render(<BillCreatorLegislatorVotes />);
        expect(notifyMock).not.toHaveBeenCalledWith(
            expect.objectContaining({
                title: expect.stringContaining("Legislator votes refreshed"),
            }),
        );
    });
});

// @lat: [[toasts#Toasts#Flash toast dedupe#A refusal that arrives in the errors hash needs its own reader]]
describe("BillCreatorLegislatorVotes — server refusal", () => {
    beforeEach(() => {
        notifyMock.mockClear();
        routerPostMock.mockClear();
        pagePropsRef.current = {
            bill: { id: 1, external_id: "X" },
            legislators: [
                {
                    id: 7,
                    first_name: "ada",
                    last_name: "byron",
                    district: { region_code: "MD", number: 3 },
                },
            ],
            legislator_votes: [],
        };
    });

    const submit = () => {
        const { container } = render(<BillCreatorLegislatorVotes />);
        const form = container.querySelector("form");
        expect(form).not.toBeNull();
        fireEvent.submit(form as HTMLFormElement);
        expect(routerPostMock).toHaveBeenCalledTimes(1);
        return routerPostMock.mock.calls[0][2] as Record<string, unknown>;
    };

    it("registers an onError handler on the save POST", () => {
        expect(typeof submit().onError).toBe("function");
    });

    it("toasts the server's own refusal copy at error level", () => {
        const onError = submit().onError as (errors: unknown) => void;

        onError({ legislator_votes: "Failed to save votes for legislator(s): 7." });

        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: "Failed to save votes for legislator(s): 7.",
        });
    });

    it("falls back to its own copy when the server sent nothing usable", () => {
        const onError = submit().onError as (errors: unknown) => void;

        onError({});

        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: "Could not save legislator votes.",
        });
    });
});

describe("BillCreatorLegislatorVotes — departed members", () => {
    beforeEach(() => {
        pagePropsRef.current = {
            bill: { id: 1, external_id: "X" },
            legislators: [
                {
                    id: 7,
                    first_name: "ada",
                    last_name: "byron",
                    active: true,
                    district: { region_code: "MD", number: 3 },
                },
                {
                    id: 8,
                    first_name: "grace",
                    last_name: "hopper",
                    active: false,
                    district: { region_code: "MD", number: 4 },
                },
            ],
            legislator_votes: [],
        };
    });

    it("marks the member who no longer holds the seat, and only that one", () => {
        const { getAllByTestId, getByLabelText } = render(<BillCreatorLegislatorVotes />);

        expect(getAllByTestId("legislator-former-stamp")).toHaveLength(1);
        expect(getByLabelText("Grace Hopper vote")).toBeTruthy();
    });

    it("offers the same vote controls for a departed member as for a serving one", () => {
        const { getByLabelText } = render(<BillCreatorLegislatorVotes />);

        expect(getByLabelText("For for Grace Hopper")).toBeTruthy();
        expect(getByLabelText("Against for Grace Hopper")).toBeTruthy();
        expect(getByLabelText("Abstain for Grace Hopper")).toBeTruthy();
    });
});
