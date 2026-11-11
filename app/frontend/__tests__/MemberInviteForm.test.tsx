import { beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, screen } from "@testing-library/react";

import MemberInviteForm from "app/frontend/components/organizations/MemberInviteForm";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

const postSpy = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());
const resetSpy = vi.hoisted(() => vi.fn<() => void>());
const formData = vi.hoisted(() => ({ invitee_email: "" }));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        useForm: () => ({
            data: formData,
            setData: (key: string, value: unknown) => {
                (formData as Record<string, unknown>)[key] = value;
            },
            transform: vi.fn<(callback: (data: typeof formData) => unknown) => void>(),
            post: postSpy,
            processing: false,
            errors: {},
            reset: resetSpy,
        }),
    };
});

beforeEach(() => {
    postSpy.mockReset();
    resetSpy.mockReset();
    formData.invitee_email = "";
});

// PARITY_COPY.members.inviteSuccess previously had no reader.
describe("MemberInviteForm — invite confirmation", () => {
    it("shows PARITY_COPY.members.inviteSuccess once the invite request succeeds", () => {
        render(<MemberInviteForm organizationId={7} />);

        expect(screen.queryByTestId("org-invite-success")).not.toBeInTheDocument();

        fireEvent.submit(screen.getByTestId("org-invite-form"));

        expect(postSpy).toHaveBeenCalled();
        const options = postSpy.mock.calls[0][1] as { onSuccess: () => void };
        act(() => options.onSuccess());

        expect(screen.getByTestId("org-invite-success")).toHaveTextContent(PARITY_COPY.members.inviteSuccess);
    });

    it("clears the confirmation once the visitor starts a new invite", () => {
        render(<MemberInviteForm organizationId={7} />);

        fireEvent.submit(screen.getByTestId("org-invite-form"));
        const options = postSpy.mock.calls[0][1] as { onSuccess: () => void };
        act(() => options.onSuccess());
        expect(screen.getByTestId("org-invite-success")).toBeInTheDocument();

        fireEvent.change(screen.getByLabelText("Invitee Email"), { target: { value: "next@example.com" } });

        expect(screen.queryByTestId("org-invite-success")).not.toBeInTheDocument();
    });
});
