import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

let mockProcessing = false;
const postMock = vi.fn<(_route: string, _opts?: unknown) => void>();
const useUserMock = vi.fn<() => sway.IUser | null | undefined>();
const copyMock = vi.fn<(text: string, options?: unknown) => Promise<boolean>>(() => Promise.resolve(true));
const notifyMock = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    useForm: (initial: unknown) => ({
        data: initial,
        setData: vi.fn<(key?: string, value?: unknown) => void>(),
        transform: vi.fn<(cb: (data: unknown) => unknown) => void>(),
        post: postMock,
        processing: mockProcessing,
        errors: {},
    }),
}));

vi.mock("app/frontend/hooks/users/useUser", () => ({
    useUser: () => useUserMock(),
}));

vi.mock("copy-to-clipboard", () => ({
    default: (...args: [string, unknown?]) => copyMock(...args),
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notifyMock(...args),
}));

import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants/routes";

const BILL: sway.IBill = {
    id: 101,
    external_id: "24-0001",
    title: "Ordinance on Street Trees",
    summary: "Requires planting native street trees across the city.",
    active: true,
} as unknown as sway.IBill;

const USER: sway.IUser = {
    id: 42,
    full_name: "Taylor Voter",
} as unknown as sway.IUser;

describe("ShareBillButton", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        mockProcessing = false;
        useUserMock.mockReturnValue(USER);
        copyMock.mockResolvedValue(true);
    });

    afterEach(() => {
        cleanup();
        Reflect.deleteProperty(window.navigator, "share");
    });

    it("renders a button with data-testid='btn-share-bill' and label PARITY_COPY.bill.shareBill", () => {
        render(<ShareBillButton bill={BILL} />);

        const button = screen.getByTestId("btn-share-bill");
        expect(button).toBeInTheDocument();
        expect(button).toHaveTextContent(PARITY_COPY.bill.shareBill);
        expect(button).not.toBeDisabled();
    });

    it("disables the button when form.processing is true", () => {
        mockProcessing = true;
        render(<ShareBillButton bill={BILL} />);

        const button = screen.getByTestId("btn-share-bill");
        expect(button).toBeDisabled();
    });

    describe("signed-in user flow", () => {
        it("calls form.post to ROUTES.userBillShares with preserveScroll, onSuccess, and onError, and handles Web Share API", async () => {
            const shareMock = vi
                .fn<(_data: { title: string; url: string }) => Promise<void>>()
                .mockResolvedValue(undefined);
            Object.defineProperty(window.navigator, "share", {
                value: shareMock,
                writable: true,
                configurable: true,
            });

            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            expect(postMock).toHaveBeenCalledTimes(1);
            expect(postMock).toHaveBeenCalledWith(
                ROUTES.userBillShares,
                expect.objectContaining({
                    preserveScroll: true,
                    onSuccess: expect.any(Function),
                    onError: expect.any(Function),
                }),
            );

            const options = postMock.mock.calls[0][1] as {
                onSuccess: (page: { props: { flash?: { bill_share_path?: string } } }) => void;
            };

            options.onSuccess({
                props: {
                    flash: {
                        bill_share_path: "/bill_shares/uuid-123",
                    },
                },
            });

            expect(shareMock).toHaveBeenCalledWith({
                title: BILL.title,
                url: `${window.location.origin}/bill_shares/uuid-123`,
            });
            await new Promise((resolve) => setTimeout(resolve, 20));
            expect(copyMock).not.toHaveBeenCalled();
            expect(notifyMock).not.toHaveBeenCalled();
        });

        it("catches and ignores AbortError when user dismisses the Web Share sheet", async () => {
            const abortError = new DOMException("The operation was aborted", "AbortError");
            const shareMock = vi
                .fn<(_data: { title: string; url: string }) => Promise<void>>()
                .mockRejectedValue(abortError);
            Object.defineProperty(window.navigator, "share", {
                value: shareMock,
                writable: true,
                configurable: true,
            });

            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            const options = postMock.mock.calls[0][1] as {
                onSuccess: (page: { props: { flash?: { bill_share_path?: string } } }) => void;
            };

            options.onSuccess({
                props: {
                    flash: {
                        bill_share_path: "/bill_shares/uuid-123",
                    },
                },
            });

            expect(shareMock).toHaveBeenCalledWith({
                title: BILL.title,
                url: `${window.location.origin}/bill_shares/uuid-123`,
            });
            await new Promise((resolve) => setTimeout(resolve, 20));
            expect(copyMock).not.toHaveBeenCalled();
            expect(notifyMock).not.toHaveBeenCalled();
        });

        it("falls back to clipboard copy when navigator.share rejects with NotAllowedError (lost user activation)", async () => {
            const notAllowedError = new DOMException("Permission denied", "NotAllowedError");
            const shareMock = vi
                .fn<(_data: { title: string; url: string }) => Promise<void>>()
                .mockRejectedValue(notAllowedError);
            Object.defineProperty(window.navigator, "share", {
                value: shareMock,
                writable: true,
                configurable: true,
            });

            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            const options = postMock.mock.calls[0][1] as {
                onSuccess: (page: { props: { flash?: { bill_share_path?: string } } }) => void;
            };

            options.onSuccess({
                props: {
                    flash: {
                        bill_share_path: "/bill_shares/uuid-123",
                    },
                },
            });

            expect(shareMock).toHaveBeenCalledWith({
                title: BILL.title,
                url: `${window.location.origin}/bill_shares/uuid-123`,
            });
            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bill_shares/uuid-123`);
                expect(notifyMock).toHaveBeenCalledWith({
                    level: "info",
                    title: PARITY_COPY.bill.shareCopied,
                });
            });
        });

        it("falls back to clipboard copy and toast when navigator.share is unavailable", async () => {
            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            const options = postMock.mock.calls[0][1] as {
                onSuccess: (page: { props: { flash?: { bill_share_path?: string } } }) => void;
            };

            options.onSuccess({
                props: {
                    flash: {
                        bill_share_path: "/bill_shares/uuid-123",
                    },
                },
            });

            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bill_shares/uuid-123`);
                expect(notifyMock).toHaveBeenCalledWith({
                    level: "info",
                    title: PARITY_COPY.bill.shareCopied,
                });
            });
        });

        it("falls back to canonical bill URL if flash.bill_share_path is missing", async () => {
            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            const options = postMock.mock.calls[0][1] as {
                onSuccess: (page: { props: { flash?: { bill_share_path?: string } } }) => void;
            };

            options.onSuccess({
                props: {
                    flash: {},
                },
            });

            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bills/${BILL.id}`);
                expect(notifyMock).toHaveBeenCalledWith({
                    level: "info",
                    title: PARITY_COPY.bill.shareCopied,
                });
            });
        });

        it("falls back to canonical bill URL when form.post triggers onError", async () => {
            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            const options = postMock.mock.calls[0][1] as {
                onError: (errors: unknown) => void;
            };

            expect(options.onError).toBeDefined();
            options.onError({ message: "Network error" });

            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bills/${BILL.id}`);
                expect(notifyMock).toHaveBeenCalledWith({
                    level: "info",
                    title: PARITY_COPY.bill.shareCopied,
                });
            });
        });

        it("does not call notify when copy resolves to false", async () => {
            copyMock.mockResolvedValueOnce(false);
            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            const options = postMock.mock.calls[0][1] as {
                onSuccess: (page: { props: { flash?: { bill_share_path?: string } } }) => void;
            };

            options.onSuccess({
                props: {
                    flash: {
                        bill_share_path: "/bill_shares/uuid-123",
                    },
                },
            });

            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bill_shares/uuid-123`);
            });
            await new Promise((resolve) => setTimeout(resolve, 20));
            expect(notifyMock).not.toHaveBeenCalled();
        });

        it("does not call notify when copy rejects", async () => {
            copyMock.mockRejectedValueOnce(new Error("Clipboard access denied"));
            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            const options = postMock.mock.calls[0][1] as {
                onSuccess: (page: { props: { flash?: { bill_share_path?: string } } }) => void;
            };

            options.onSuccess({
                props: {
                    flash: {
                        bill_share_path: "/bill_shares/uuid-123",
                    },
                },
            });

            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bill_shares/uuid-123`);
            });
            await new Promise((resolve) => setTimeout(resolve, 20));
            expect(notifyMock).not.toHaveBeenCalled();
        });
    });

    describe("signed-out visitor flow", () => {
        beforeEach(() => {
            useUserMock.mockReturnValue(null);
        });

        it("does not call form.post and shares canonical bill URL via Web Share API", async () => {
            const shareMock = vi
                .fn<(_data: { title: string; url: string }) => Promise<void>>()
                .mockResolvedValue(undefined);
            Object.defineProperty(window.navigator, "share", {
                value: shareMock,
                writable: true,
                configurable: true,
            });

            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            expect(postMock).not.toHaveBeenCalled();
            expect(shareMock).toHaveBeenCalledWith({
                title: BILL.title,
                url: `${window.location.origin}/bills/${BILL.id}`,
            });
            await new Promise((resolve) => setTimeout(resolve, 20));
            expect(copyMock).not.toHaveBeenCalled();
            expect(notifyMock).not.toHaveBeenCalled();
        });

        it("catches and ignores AbortError when signed-out visitor dismisses the Web Share sheet", async () => {
            const abortError = new DOMException("The operation was aborted", "AbortError");
            const shareMock = vi
                .fn<(_data: { title: string; url: string }) => Promise<void>>()
                .mockRejectedValue(abortError);
            Object.defineProperty(window.navigator, "share", {
                value: shareMock,
                writable: true,
                configurable: true,
            });

            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            expect(postMock).not.toHaveBeenCalled();
            expect(shareMock).toHaveBeenCalledWith({
                title: BILL.title,
                url: `${window.location.origin}/bills/${BILL.id}`,
            });
            await new Promise((resolve) => setTimeout(resolve, 20));
            expect(copyMock).not.toHaveBeenCalled();
            expect(notifyMock).not.toHaveBeenCalled();
        });

        it("does not call form.post and copies canonical bill URL via clipboard fallback", async () => {
            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            expect(postMock).not.toHaveBeenCalled();
            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bills/${BILL.id}`);
                expect(notifyMock).toHaveBeenCalledWith({
                    level: "info",
                    title: PARITY_COPY.bill.shareCopied,
                });
            });
        });

        it("falls back to clipboard copy when navigator.share rejects with NotAllowedError for signed-out visitor", async () => {
            const notAllowedError = new DOMException("Permission denied", "NotAllowedError");
            const shareMock = vi
                .fn<(_data: { title: string; url: string }) => Promise<void>>()
                .mockRejectedValue(notAllowedError);
            Object.defineProperty(window.navigator, "share", {
                value: shareMock,
                writable: true,
                configurable: true,
            });

            render(<ShareBillButton bill={BILL} />);

            fireEvent.click(screen.getByTestId("btn-share-bill"));

            expect(postMock).not.toHaveBeenCalled();
            expect(shareMock).toHaveBeenCalledWith({
                title: BILL.title,
                url: `${window.location.origin}/bills/${BILL.id}`,
            });
            await vi.waitFor(() => {
                expect(copyMock).toHaveBeenCalledWith(`${window.location.origin}/bills/${BILL.id}`);
                expect(notifyMock).toHaveBeenCalledWith({
                    level: "info",
                    title: PARITY_COPY.bill.shareCopied,
                });
            });
        });
    });
});
