import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockReload = vi.fn<(...args: unknown[]) => void>();
let mockPageProps: { summary_revisions?: unknown } = {};

vi.mock("@inertiajs/react", () => ({
    router: {
        reload: (...args: unknown[]) => mockReload(...args),
    },
    usePage: () => ({ props: mockPageProps }),
}));

import { useBillSummaryRevisions } from "app/frontend/components/admin/creator/llm-summary/useBillSummaryRevisions";
import { IBillSummaryRevision } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
describe("useBillSummaryRevisions", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        mockPageProps = {};
    });

    it("returns null revisions and false loading as initial state when props are absent", () => {
        mockPageProps = {};
        const { result } = renderHook(() => useBillSummaryRevisions());

        expect(result.current.revisions).toBeNull();
        expect(result.current.loading).toBe(false);
    });

    it("returns page prop revisions when available", () => {
        const sampleRevisions: IBillSummaryRevision[] = [
            {
                id: 1,
                bill_id: 10,
                summary_markdown: "Sample markdown summary",
                origin: "operator_edit",
                actor_name: "Admin User",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                created_at: "2026-09-14T00:00:00Z",
            },
        ];
        mockPageProps = { summary_revisions: sampleRevisions };

        const { result } = renderHook(() => useBillSummaryRevisions());

        expect(result.current.revisions).toEqual(sampleRevisions);
        expect(result.current.loading).toBe(false);
    });

    it("fetches revisions on-demand via router.reload with only summary_revisions", () => {
        const { result } = renderHook(() => useBillSummaryRevisions());

        expect(result.current.loading).toBe(false);
        expect(mockReload).not.toHaveBeenCalled();

        act(() => {
            result.current.load();
        });

        expect(result.current.loading).toBe(true);
        expect(mockReload).toHaveBeenCalledTimes(1);
        expect(mockReload).toHaveBeenCalledWith({
            only: ["summary_revisions"],
            onFinish: expect.any(Function),
        });

        // Simulate onFinish callback completion
        const reloadCall = mockReload.mock.calls[0]?.[0] as { onFinish?: () => void };
        act(() => {
            reloadCall?.onFinish?.();
        });

        expect(result.current.loading).toBe(false);
    });

    it("handles error completion cleanly by resetting loading to false via onFinish", () => {
        const { result } = renderHook(() => useBillSummaryRevisions());

        act(() => {
            result.current.load();
        });

        expect(result.current.loading).toBe(true);

        // When router.reload finishes after encountering an error, onFinish is invoked
        const reloadCall = mockReload.mock.calls[0]?.[0] as { onFinish?: () => void };
        act(() => {
            reloadCall?.onFinish?.();
        });

        expect(result.current.loading).toBe(false);
    });
});
