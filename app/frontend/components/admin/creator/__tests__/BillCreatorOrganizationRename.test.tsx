import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

type TPatchOptions = { onSuccess?: (page: unknown) => void; onFinish?: () => void };
const patchMock = vi.fn<(url: string, body: unknown, options: TPatchOptions) => void>();

vi.mock("@inertiajs/react", () => ({
    router: { patch: (url: string, body: unknown, options: TPatchOptions) => patchMock(url, body, options) },
}));

const setDataMock = vi.fn<(key: string, value: unknown) => void>();
vi.mock("app/frontend/components/admin/creator/context/useSwayFormContext", () => ({
    useSwayFormContext: () => ({ data: { organizations: [] }, setData: setDataMock }),
}));

// The icon uploader talks to direct uploads and is not what these tests are about.
vi.mock("app/frontend/components/admin/creator/OrgIconUpload", () => ({
    __esModule: true,
    default: () => <div data-testid="org-icon-upload" />,
}));

import BillCreatorOrganization from "app/frontend/components/admin/creator/BillCreatorOrganization";

const renderCard = () =>
    render(
        <BillCreatorOrganization
            index={0}
            organization={{ value: 12, label: "Taco Org", support: "FOR" } as never}
            billId={42}
            tabKey="organizations"
            removing={false}
            onRemove={vi.fn<() => void>()}
        />,
    );

// Type a new name and press Save name, then hand back the page the server's
// redirect produced.
const renameTo = (name: string, landingPage: unknown) => {
    fireEvent.click(screen.getByTestId("btn-rename-org-0"));
    fireEvent.change(screen.getByTestId("input-rename-org-0"), { target: { value: name } });
    fireEvent.click(screen.getByTestId("btn-save-rename-org-0"));

    const options = patchMock.mock.calls[0][2];
    act(() => {
        options.onSuccess?.(landingPage);
        options.onFinish?.();
    });
};

const LANDED = { props: {} };
const REFUSED = { props: { flash: { page_expired: true } } };
const ALERTED = { props: { flash: { alert: "Could not rename organization: Name has already been taken" } } };

afterEach(() => {
    cleanup();
    patchMock.mockReset();
    setDataMock.mockReset();
});

describe("BillCreatorOrganization — renaming", () => {
    // @lat: [[bill-creator-organization-form#Rename updates the saved organization and current form]]
    it("writes the new name into the form when the server took the rename", () => {
        renderCard();
        renameTo("Taco Org of Maryland", LANDED);

        expect(patchMock).toHaveBeenCalledTimes(1);
        expect(patchMock.mock.calls[0][0]).toBe("/organizations/12");
        expect(setDataMock).toHaveBeenCalledWith("organizations.0.label", "Taco Org of Maryland");
    });

    // @lat: [[bill-creator-organization-form#Rename updates the saved organization and current form]]
    it("leaves the old name in place when the page token had gone stale", () => {
        renderCard();
        renameTo("Taco Org of Maryland", REFUSED);

        // @lat: [[identity-and-access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]
        expect(setDataMock).not.toHaveBeenCalled();
        expect(screen.getByTestId("input-rename-org-0")).toBeTruthy();
    });

    it("leaves the old name and rename input open when the server rejects the rename with a flash alert", () => {
        renderCard();
        renameTo("Duplicate Name", ALERTED);

        expect(setDataMock).not.toHaveBeenCalled();
        expect(screen.getByTestId("input-rename-org-0")).toBeTruthy();
    });

    it("renders Abstain for a neutral support position instead of Against", () => {
        render(
            <BillCreatorOrganization
                index={0}
                organization={{ value: 12, label: "Neutral Org", support: "ABSTAIN" } as never}
                billId={42}
                tabKey="organizations"
                removing={false}
                onRemove={vi.fn<() => void>()}
            />,
        );

        expect(screen.getByText("Abstain")).toBeTruthy();
    });
});
