import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

type TDeleteOptions = { onSuccess?: (page: unknown) => void; onFinish?: () => void };
const patchMock = vi.fn<(url: string, data: Record<string, unknown>, options: TDeleteOptions) => void>();
const onRemoveMock = vi.fn<() => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        patch: (url: string, data: Record<string, unknown>, options: TDeleteOptions) => patchMock(url, data, options),
    },
}));

const KEPT = { value: 13, label: "Kept Org", support: "FOR", summary: "" };
const GOING = { value: 12, label: "Taco Org", support: "FOR", summary: "", position_id: 42 };

const setDataMock = vi.fn<(key: string, value: unknown) => void>();
let formOrganizations: unknown[] = [];
vi.mock("app/frontend/components/admin/creator/context/useSwayFormContext", () => ({
    useSwayFormContext: () => ({ data: { organizations: formOrganizations }, setData: setDataMock }),
}));

vi.mock("app/frontend/components/admin/creator/OrgIconUpload", () => ({
    __esModule: true,
    default: () => <div data-testid="org-icon-upload" />,
}));

import BillCreatorOrganization from "app/frontend/components/admin/creator/BillCreatorOrganization";

const renderCard = (organization: Record<string, unknown>, removing: boolean = false) => {
    formOrganizations = [organization, KEPT];
    return render(
        <BillCreatorOrganization
            index={0}
            organization={organization as never}
            billId={42}
            tabKey="summary"
            removing={removing}
            onRemove={onRemoveMock}
        />,
    );
};

afterEach(() => {
    cleanup();
    patchMock.mockReset();
    onRemoveMock.mockReset();
    setDataMock.mockReset();
    formOrganizations = [];
});

describe("BillCreatorOrganization — Remove organization", () => {
    it("delegates row removal to the parent form", () => {
        renderCard(GOING);

        fireEvent.click(screen.getByTestId("btn-remove-org-0"));

        expect(onRemoveMock).toHaveBeenCalledTimes(1);
    });

    it("disables the row button while the parent removal request is active", () => {
        renderCard(GOING, true);
        expect(screen.getByTestId("btn-remove-org-0")).toBeDisabled();
    });

    it("delegates removal of an unsaved organization to the parent form", () => {
        renderCard({ value: 12, label: "Taco Org", support: "FOR", summary: "" });

        fireEvent.click(screen.getByTestId("btn-remove-org-0"));

        expect(onRemoveMock).toHaveBeenCalledTimes(1);
    });
});

describe("BillCreatorOrganization — namespaced request state", () => {
    it("includes the tab under the Bill Creator namespace when renaming", () => {
        renderCard(GOING);

        fireEvent.click(screen.getByTestId("btn-rename-org-0"));
        fireEvent.change(screen.getByLabelText("Organization name"), { target: { value: "Renamed Taco Org" } });
        fireEvent.click(screen.getByTestId("btn-save-rename-org-0"));

        expect(patchMock).toHaveBeenCalledWith(
            "/organizations/12",
            { name: "Renamed Taco Org", bill_id: 42, bill_creator_tab: "summary" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });
});
