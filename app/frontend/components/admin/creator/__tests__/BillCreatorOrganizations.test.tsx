// @lat: [[bill-creator-organization-form#The component tests keep the picker real]]

import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Support } from "app/frontend/sway_constants";
import type { TOrganizationOption } from "app/frontend/components/admin/creator/types";

const usePageMock = vi.fn<() => Record<string, unknown>>();
const setDataMock = vi.fn<(key: string, value: unknown) => void>();
const postMock = vi.fn<(url: string, options: { preserveScroll: boolean; async: boolean }) => void>();
type TDeleteOptions = { onSuccess?: (page: unknown) => void; onFinish?: () => void };
const deleteMock = vi.fn<(url: string, options: TDeleteOptions) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: { delete: (url: string, options: TDeleteOptions) => deleteMock(url, options) },
    // A useForm that really remembers: React.useState, so setData both keeps the
    // value and redraws the parent. That lets a test act out create, remove,
    // create.
    useForm: (initial: unknown) => {
        const [data, setDataState] = React.useState(initial as Record<string, unknown>);
        const setData = (key: string, value: unknown) => {
            setDataMock(key, value);
            setDataState((prev) => ({ ...prev, [key]: value }));
        };
        return { data, setData, post: postMock, processing: false };
    },
}));

// Bare stand-ins for the parts these tests do not care about. The picker and the
// selected chips stay REAL: they are what makes the ids and offers the remove
// button.
vi.mock("app/frontend/components/admin/creator/BillCreatorFormHeader", () => ({
    __esModule: true,
    default: () => <div data-testid="form-header" />,
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorOrganization", () => {
    // The real sub-form keeps editingName, nameDraft and renaming as local state, set once
    // from props. This stand-in keeps one, since without local state you can't tell if it rebuilt.
    const StubOrganizationSubform: React.FC<{ organization: TOrganizationOption }> = ({ organization }) => {
        const [rename, setRename] = React.useState<string>(organization.label);
        return (
            <div
                data-testid={`org-subform-${organization.value}`}
                data-label={organization.label}
                data-summary={organization.summary}
                data-support={organization.support}
            >
                {organization.label}
                <input
                    aria-label={`rename ${organization.label}`}
                    value={rename}
                    onChange={(e) => setRename(e.target.value)}
                />
            </div>
        );
    };
    return { __esModule: true, default: StubOrganizationSubform };
});
vi.mock("app/frontend/components/admin/creator/hooks/useTempStorage", () => ({
    useTempStorage: () => ({ storage: null, blurredFieldName: "" }),
}));

import BillCreatorOrganizations from "app/frontend/components/admin/creator/BillCreatorOrganizations";
import { organizationsFormKey } from "app/frontend/components/admin/creator/organizations/organizationsFormKey";
import billCreatorOrganizationsSource from "app/frontend/components/admin/creator/BillCreatorOrganizations.tsx?raw";

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    setDataMock.mockReset();
    postMock.mockReset();
    deleteMock.mockReset();
});

// bill.organizations fills in the list of organizations already CHOSEN.
// props.organizations is every organization in the locale, which the picker
// offers as choices.
const setupPage = (opts: {
    seededOrgs?: Array<{ id: number; name: string; positions?: Array<Record<string, unknown>> }>;
    availableOrgs?: Array<{ id: number; name: string; positions?: Array<Record<string, unknown>> }>;
}) => {
    usePageMock.mockReturnValue({
        props: {
            errors: {},
            bill: { id: 1, organizations: opts.seededOrgs ?? [] },
            tab_key: "creator",
            organizations: opts.availableOrgs ?? [],
        },
    });
};

const createOrg = (name: string) => {
    const input = screen.getByPlaceholderText(/search or create/i);
    fireEvent.change(input, { target: { value: name } });
    fireEvent.keyDown(input, { key: "Enter" });
};

const lastOrganizationsPayload = (): TOrganizationOption[] => {
    const calls = setDataMock.mock.calls.filter((c) => c[0] === "organizations");
    return (calls.at(-1)?.[1] ?? []) as TOrganizationOption[];
};

describe("BillCreatorOrganizations — placeholder ids + session cache", () => {
    it("gives every inline-created org a distinct id even after a removal frees an old one", () => {
        setupPage({ seededOrgs: [{ id: 5, name: "Existing", positions: [] }] });
        render(<BillCreatorOrganizations />);

        createOrg("B"); // gets temporary id -1
        fireEvent.click(screen.getByLabelText("Remove Existing")); // gives up id 5
        createOrg("C"); // gets -2, NOT a reused id, and must not bring B back

        const payload = lastOrganizationsPayload();
        expect(payload.map((o) => o.label)).toEqual(["B", "C"]);
        // Two different ids. Before the fix, B and C landed on the same one.
        expect(new Set(payload.map((o) => o.value)).size).toBe(2);
    });

    it("restores a removed org's draft summary/support when it is re-added (cache written on remove)", () => {
        setupPage({
            seededOrgs: [
                { id: 5, name: "Existing", positions: [{ bill_id: 1, summary: "my draft", support: Support.Against }] },
            ],
            // The locale-wide copy has no draft, so only the remembered row can
            // supply one.
            availableOrgs: [{ id: 5, name: "Existing", positions: [] }],
        });
        render(<BillCreatorOrganizations />);

        fireEvent.click(screen.getByLabelText("Remove Existing")); // remembers the draft
        createOrg("Existing"); // add it back from the list that has no draft

        const payload = lastOrganizationsPayload();
        expect(payload).toHaveLength(1);
        expect(payload[0].value).toBe(5);
        expect(payload[0].summary).toBe("my draft");
        expect(payload[0].support).toBe(Support.Against);
    });

    it("the parent holds no useEffect — the cache is event-driven, not effect-mirrored", () => {
        expect(billCreatorOrganizationsSource).not.toMatch(/useEffect/);
    });

    it("syncs setCreatorDirty when organizations form becomes dirty and resets to false on unmount", () => {
        const setCreatorDirty = vi.fn<(dirty: boolean | ((prev: boolean) => boolean)) => void>();
        setupPage({ seededOrgs: [{ id: 5, name: "Existing", positions: [] }] });
        const { unmount } = render(<BillCreatorOrganizations setCreatorDirty={setCreatorDirty} />);

        expect(setCreatorDirty).toHaveBeenLastCalledWith(false);

        createOrg("New Org");
        expect(setCreatorDirty).toHaveBeenLastCalledWith(true);

        unmount();
        expect(setCreatorDirty).toHaveBeenLastCalledWith(false);
    });
});

describe("BillCreatorOrganizations — namespaced request state", () => {
    it("posts the selected tab under the Bill Creator namespace", () => {
        setupPage({ seededOrgs: [{ id: 5, name: "Existing", positions: [] }] });
        render(<BillCreatorOrganizations />);

        fireEvent.click(screen.getByRole("button", { name: /save supporting\/opposing arguments/i }));

        expect(postMock).toHaveBeenCalledWith("/organizations?bill_creator_tab=creator", {
            preserveScroll: true,
            async: false,
        });
    });
});

// @lat: [[bill-creator-organization-form#The component tests keep the picker real]]
describe("BillCreatorOrganizations — removing a row does not remount its siblings (C1-WR-04)", () => {
    it("keeps a later row's in-progress inline rename when an earlier row is removed", () => {
        setupPage({
            seededOrgs: [
                { id: 5, name: "First", positions: [] },
                { id: 6, name: "Second", positions: [] },
                { id: 7, name: "Third", positions: [] },
            ],
        });
        render(<BillCreatorOrganizations />);

        fireEvent.change(screen.getByLabelText("rename Third"), { target: { value: "Third, renamed" } });
        fireEvent.click(screen.getByLabelText("Remove First"));

        expect(screen.getByLabelText("rename Third")).toHaveValue("Third, renamed");
    });
});

const KeyedPanel: React.FC = () => {
    const bill = (usePageMock() as { props: { bill?: { id: number; organizations?: Array<{ id: number }> } } }).props
        .bill;
    return <BillCreatorOrganizations key={organizationsFormKey(bill)} />;
};

// @lat: [[bill-creator-summary-tab#Why the organizations panel carries a remount key]]
describe("BillCreatorOrganizations — a changed organization set re-seeds the form", () => {
    it("shows an organization the server added while the panel was mounted", () => {
        setupPage({ seededOrgs: [{ id: 5, name: "First", positions: [] }] });
        const { rerender } = render(<KeyedPanel />);

        expect(screen.getByTestId("org-subform-5")).toBeInTheDocument();
        expect(screen.queryByTestId("org-subform-6")).not.toBeInTheDocument();

        setupPage({
            seededOrgs: [
                { id: 5, name: "First", positions: [] },
                { id: 6, name: "Second", positions: [] },
            ],
        });
        rerender(<KeyedPanel />);

        expect(screen.getByTestId("org-subform-5")).toBeInTheDocument();
        expect(screen.getByTestId("org-subform-6")).toBeInTheDocument();
    });

    it("reads the same key for one set of organizations however the server ordered it", () => {
        expect(organizationsFormKey({ id: 1, organizations: [{ id: 6 }, { id: 5 }] })).toBe(
            organizationsFormKey({ id: 1, organizations: [{ id: 5 }, { id: 6 }] }),
        );
        expect(organizationsFormKey({ id: 2, organizations: [{ id: 5 }] })).not.toBe(
            organizationsFormKey({ id: 1, organizations: [{ id: 5 }] }),
        );
        expect(organizationsFormKey({ id: 1, organizations: [] })).toBe("1:none");
    });

    it("keeps an in-progress edit when a reload brings back the same organization set", () => {
        setupPage({ seededOrgs: [{ id: 5, name: "First", positions: [] }] });
        const { rerender } = render(<KeyedPanel />);

        fireEvent.change(screen.getByLabelText("rename First"), { target: { value: "First, renamed" } });

        setupPage({ seededOrgs: [{ id: 5, name: "First", positions: [] }] });
        rerender(<KeyedPanel />);

        expect(screen.getByLabelText("rename First")).toHaveValue("First, renamed");
    });
});

// @lat: [[organization-position-removal#Both remove controls go through the same request]]
describe("BillCreatorOrganizations — the tag above the cards removes for real", () => {
    it("sends a saved position's removal to the server before dropping the tag", () => {
        setupPage({
            seededOrgs: [
                { id: 5, name: "Existing", positions: [{ id: 91, bill_id: 1, summary: "x", support: Support.For }] },
            ],
        });
        render(<BillCreatorOrganizations />);

        fireEvent.click(screen.getByLabelText("Remove Existing"));

        expect(deleteMock).toHaveBeenCalledTimes(1);
        expect(deleteMock.mock.calls[0][0]).toBe("/organization_bill_positions/91?bill_creator_tab=creator");
        expect(lastOrganizationsPayload()).toHaveLength(0);

        act(() => deleteMock.mock.calls[0][1].onSuccess?.({ props: {} }));

        expect(setDataMock).toHaveBeenCalledWith("organizations", []);
    });

    it("keeps a saved position selected when the server refuses a stale page token", () => {
        setupPage({
            seededOrgs: [
                { id: 5, name: "Existing", positions: [{ id: 91, bill_id: 1, summary: "x", support: Support.For }] },
            ],
        });
        render(<BillCreatorOrganizations />);

        fireEvent.click(screen.getByLabelText("Remove Existing"));
        act(() => deleteMock.mock.calls[0][1].onSuccess?.({ props: { flash: { page_expired: true } } }));

        expect(setDataMock).not.toHaveBeenCalledWith("organizations", []);
    });

    it("sends nothing for a tag whose organization was never saved against this bill", () => {
        setupPage({ seededOrgs: [{ id: 5, name: "Existing", positions: [] }] });
        render(<BillCreatorOrganizations />);

        fireEvent.click(screen.getByLabelText("Remove Existing"));

        expect(deleteMock).not.toHaveBeenCalled();
        expect(setDataMock).toHaveBeenCalledWith("organizations", []);
    });

    it("clears position_id in the session cache on removal so re-adding and removing again does not issue a second DELETE", () => {
        setupPage({
            seededOrgs: [
                { id: 5, name: "Existing", positions: [{ id: 91, bill_id: 1, summary: "x", support: Support.For }] },
            ],
            availableOrgs: [
                { id: 5, name: "Existing", positions: [{ id: 91, bill_id: 1, summary: "x", support: Support.For }] },
            ],
        });
        render(<BillCreatorOrganizations />);

        fireEvent.click(screen.getByLabelText("Remove Existing"));
        expect(deleteMock).toHaveBeenCalledTimes(1);
        act(() => deleteMock.mock.calls[0][1].onSuccess?.({ props: {} }));

        createOrg("Existing");
        expect(lastOrganizationsPayload()[0]?.position_id).toBeUndefined();

        fireEvent.click(screen.getByLabelText("Remove Existing"));
        expect(deleteMock).toHaveBeenCalledTimes(1);
    });
});
