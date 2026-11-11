// @lat: [[email-verifications-controller-notes#Frontend: EmailLegislatorsModal.tsx]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { sway } from "sway";

const usePageMock = vi.fn<() => Record<string, unknown>>();
const useUserMock = vi.fn<() => Record<string, unknown>>();
const postMock = vi.fn<(_route: string, opts?: { onSuccess?: () => void }) => void | undefined>();
const patchMock =
    vi.fn<(_route: string, opts?: { onSuccess?: () => void; onError?: () => void }) => void | undefined>();
const deleteMock = vi.fn<(_route: string, opts?: { onFinish?: () => void }) => void | undefined>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: {
        delete: (_route: string, opts?: { onFinish?: () => void }) => deleteMock(_route, opts),
    },
    // A stand-in for useForm that really holds state — the same approach as
    // BillCreatorOrganizations.test.tsx — so setData causes a re-render and a
    // multi-step flow can be driven from a test.
    useForm: (initial: unknown) => {
        const [data, setDataState] = React.useState(initial as Record<string, unknown>);
        const setData = (key: string, value: unknown) => {
            setDataState((prev) => ({ ...prev, [key]: value }));
        };
        return { data, setData, post: postMock, patch: patchMock, processing: false, errors: {} };
    },
}));

vi.mock("app/frontend/hooks/users/useUser", () => ({
    useUser: () => useUserMock(),
}));

import EmailLegislatorsModal from "app/frontend/components/bill/EmailLegislatorsModal";

const BILL = { id: 7, external_id: "HB-7", title: "Test Bill" } as unknown as sway.IBill;

const PREVIEW: sway.IEmailPreview = {
    subject: "Support Bill HB-7",
    intro: "Hello Rep Jones, my name is Taylor Voter and I reside in your district.",
    body: "Please support bill HB-7 Test Bill, which can be found here - ",
    conclusion: "Thank you, Taylor Voter.",
    bill_link: "https://example.gov/hb7",
};

const openModal = () => {
    fireEvent.click(screen.getByTestId("btn-email-legislators"));
};

beforeEach(() => {
    vi.clearAllMocks();
    usePageMock.mockReturnValue({ props: { email_preview: PREVIEW, user_legislator_emails: [] } });
});

afterEach(cleanup);

describe("EmailLegislatorsModal", () => {
    it("starts at the email-entry step for an unverified user", () => {
        useUserMock.mockReturnValue({ email: null, is_email_verified: false, full_name: "Taylor Voter" });
        render(<EmailLegislatorsModal bill={BILL} />);
        openModal();

        expect(screen.getByTestId("email-entry-step")).toBeInTheDocument();
        expect(screen.queryByTestId("email-code-step")).not.toBeInTheDocument();
        expect(screen.queryByTestId("email-send-step")).not.toBeInTheDocument();
    });

    it("advances to the code step after the verification email sends", () => {
        useUserMock.mockReturnValue({ email: null, is_email_verified: false, full_name: "Taylor Voter" });
        postMock.mockImplementation((_route: string, opts?: { onSuccess?: () => void }) => opts?.onSuccess?.());
        render(<EmailLegislatorsModal bill={BILL} />);
        openModal();

        fireEvent.change(screen.getByLabelText("Email"), { target: { value: "voter@example.com" } });
        fireEvent.submit(screen.getByTestId("email-entry-step"));

        expect(postMock).toHaveBeenCalledWith("/users/email_verification", expect.anything());
        expect(screen.getByTestId("email-code-step")).toBeInTheDocument();
        expect(screen.queryByTestId("email-entry-step")).not.toBeInTheDocument();
    });

    it("Start Over clears the pending address server-side and returns to email entry", () => {
        useUserMock.mockReturnValue({ email: null, is_email_verified: false, full_name: "Taylor Voter" });
        postMock.mockImplementation((_route: string, opts?: { onSuccess?: () => void }) => opts?.onSuccess?.());
        deleteMock.mockImplementation((_route: string, opts?: { onFinish?: () => void }) => opts?.onFinish?.());
        render(<EmailLegislatorsModal bill={BILL} />);
        openModal();

        fireEvent.change(screen.getByLabelText("Email"), { target: { value: "voter@example.com" } });
        fireEvent.submit(screen.getByTestId("email-entry-step"));
        fireEvent.click(screen.getByRole("button", { name: "Start Over" }));

        expect(deleteMock).toHaveBeenCalledWith("/users/email_verification", expect.anything());
        expect(screen.getByTestId("email-entry-step")).toBeInTheDocument();
    });

    it("verifies the code via PATCH", () => {
        useUserMock.mockReturnValue({ email: null, is_email_verified: false, full_name: "Taylor Voter" });
        postMock.mockImplementation((_route: string, opts?: { onSuccess?: () => void }) => opts?.onSuccess?.());
        render(<EmailLegislatorsModal bill={BILL} />);
        openModal();

        fireEvent.change(screen.getByLabelText("Email"), { target: { value: "voter@example.com" } });
        fireEvent.submit(screen.getByTestId("email-entry-step"));
        fireEvent.change(screen.getByLabelText("Code"), { target: { value: "123456" } });
        fireEvent.submit(screen.getByTestId("email-code-step"));

        expect(patchMock).toHaveBeenCalledWith("/users/email_verification", expect.anything());
    });

    it("shows the send step with the server-built preview for a verified, named user", () => {
        useUserMock.mockReturnValue({
            email: "voter@example.com",
            is_email_verified: true,
            full_name: "Taylor Voter",
        });
        render(<EmailLegislatorsModal bill={BILL} />);
        openModal();

        expect(screen.getByTestId("email-send-step")).toBeInTheDocument();
        expect(screen.getByTestId("email-preview")).toHaveTextContent(PREVIEW.intro);
        // Named user: no inline name input.
        expect(screen.queryByLabelText("Name")).not.toBeInTheDocument();

        fireEvent.submit(screen.getByTestId("email-send-step"));
        expect(postMock).toHaveBeenCalledWith("/user_legislator_emails", expect.anything());
    });

    it("requires an inline name before sending when the user has none", () => {
        useUserMock.mockReturnValue({
            email: "voter@example.com",
            is_email_verified: true,
            full_name: undefined,
        });
        render(<EmailLegislatorsModal bill={BILL} />);
        openModal();

        const send = screen.getByRole("button", { name: "Send" });
        expect(send).toBeDisabled();

        fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Jordan Q. Public" } });
        expect(screen.getByRole("button", { name: "Send" })).toBeEnabled();
    });

    it("renders per-legislator send statuses with stamp badges", () => {
        useUserMock.mockReturnValue({
            email: "voter@example.com",
            is_email_verified: true,
            full_name: "Taylor Voter",
        });
        usePageMock.mockReturnValue({
            props: {
                email_preview: PREVIEW,
                user_legislator_emails: [
                    { id: 1, bill_id: 7, status: "sent", legislator_id: 3, legislator_full_name: "Alex Jones" },
                    { id: 2, bill_id: 7, status: "failed", legislator_id: 4, legislator_full_name: "Sam Smith" },
                ],
            },
        });
        render(<EmailLegislatorsModal bill={BILL} />);
        openModal();

        const statuses = screen.getByTestId("legislator-email-statuses");
        expect(statuses).toHaveTextContent("Alex Jones");
        expect(statuses).toHaveTextContent("sent");
        expect(statuses).toHaveTextContent("Sam Smith");
        expect(statuses).toHaveTextContent("failed");
    });
});
