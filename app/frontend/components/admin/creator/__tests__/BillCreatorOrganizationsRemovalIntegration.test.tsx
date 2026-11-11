import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Support } from "app/frontend/sway_constants";

const mocks = vi.hoisted(() => ({
    pageProps: { current: {} as Record<string, unknown> },
    delete: vi.fn<(url: string, options: { onSuccess?: (page: unknown) => void; onFinish?: () => void }) => void>(),
}));

vi.mock("@inertiajs/react", async () => {
    const React = await import("react");

    const setAtPath = (source: Record<string, unknown>, path: string, value: unknown) => {
        const keys = path.split(".");
        const result = { ...source };
        let target = result;
        let from = source;

        keys.forEach((key, index) => {
            if (index === keys.length - 1) {
                target[key] = value;
                return;
            }
            const original = from[key];
            const next = Array.isArray(original) ? [...original] : { ...(original as Record<string, unknown>) };
            target[key] = next;
            target = next as Record<string, unknown>;
            from = original as Record<string, unknown>;
        });

        return result;
    };

    return {
        router: { delete: mocks.delete },
        usePage: () => ({ props: mocks.pageProps.current }),
        useForm: (initial: Record<string, unknown>) => {
            const [data, setDataState] = React.useState(initial);
            const setData = React.useCallback((key: string, value: unknown) => {
                setDataState((previous) => setAtPath(previous, key, value));
            }, []);
            return {
                data,
                setData,
                post: vi.fn<(url: string, options?: unknown) => void>(),
                processing: false,
                errors: {},
                reset: vi.fn<() => void>(),
            };
        },
    };
});

vi.mock("app/frontend/components/admin/creator/BillCreatorFormHeader", () => ({ default: () => <div /> }));
vi.mock("app/frontend/components/admin/creator/OrgIconUpload", () => ({ default: () => <div /> }));
vi.mock("app/frontend/components/admin/creator/FeatureInfo", () => ({ default: () => null }));
vi.mock("app/frontend/components/admin/creator/hooks/useTempStorage", () => ({
    useTempStorage: () => ({ storage: null, blurredFieldName: "" }),
}));

import BillCreatorOrganizations from "app/frontend/components/admin/creator/BillCreatorOrganizations";
import BillCreatorOrganizationDraftCache from "app/frontend/components/admin/creator/context/BillCreatorOrganizationDraftCache";
import { organizationsFormKey } from "app/frontend/components/admin/creator/organizations/organizationsFormKey";

const RoutedOrganizationPanel: React.FC<{ bill: { id: number; organizations: (typeof organization)[] } }> = ({
    bill,
}) => (
    <BillCreatorOrganizationDraftCache key={bill.id}>
        <BillCreatorOrganizations key={organizationsFormKey(bill)} />
    </BillCreatorOrganizationDraftCache>
);

const organization = {
    id: 5,
    name: "Taco Org",
    positions: [{ id: 91, bill_id: 1, summary: "Persisted position summary", support: Support.Against }],
};

const setupPage = () => {
    mocks.pageProps.current = {
        errors: {},
        bill: { id: 1, organizations: [organization] },
        tab_key: "summary",
        organizations: [{ id: organization.id, name: organization.name, positions: [] }],
    };
    mocks.delete.mockReset();
    mocks.delete.mockImplementation(() => {});
};

const editCurrentPosition = () => {
    fireEvent.change(screen.getByLabelText("Taco Org position summary"), {
        target: { value: "Unsaved position summary" },
    });
    fireEvent.click(screen.getByRole("switch", { name: "Taco Org support" }));

    expect(screen.getByLabelText("Taco Org position summary")).toHaveValue("Unsaved position summary");
    expect(screen.getByRole("switch", { name: "Taco Org support" })).toHaveAttribute("aria-checked", "true");
};

const readdOrganization = () => {
    const picker = screen.getByPlaceholderText("Search or create an organization...");
    fireEvent.change(picker, { target: { value: "Taco Org" } });
    fireEvent.click(screen.getByRole("button", { name: "Taco Org" }));

    expect(screen.getByLabelText("Taco Org position summary")).toHaveValue("Unsaved position summary");
    expect(screen.getByRole("switch", { name: "Taco Org support" })).toHaveAttribute("aria-checked", "true");
};

const completeRemoval = () => {
    expect(mocks.delete).toHaveBeenCalledTimes(1);
    expect(mocks.delete.mock.calls[0][0]).toBe("/organization_bill_positions/91?bill_creator_tab=summary");
    act(() => {
        mocks.delete.mock.calls[0][1].onSuccess?.({ props: {} });
        mocks.delete.mock.calls[0][1].onFinish?.();
    });
};

const renderRoutedPanel = () => {
    const bill = mocks.pageProps.current.bill as { id: number; organizations: (typeof organization)[] };
    return render(<RoutedOrganizationPanel bill={bill} />);
};

afterEach(() => {
    cleanup();
});

// @lat: [[bill-creator-organization-form#The component tests keep the picker real]]
describe("BillCreatorOrganizations — parent and row share removed draft state", () => {
    it("restores edited support and summary after the row button removes and re-adds the organization", () => {
        setupPage();
        const view = renderRoutedPanel();

        editCurrentPosition();
        fireEvent.click(screen.getByTestId("btn-remove-org-0"));
        expect(screen.getByTestId("btn-remove-org-0")).toBeDisabled();
        completeRemoval();

        expect(screen.queryByLabelText("Taco Org position summary")).not.toBeInTheDocument();
        mocks.pageProps.current.bill = { id: 1, organizations: [] };
        view.rerender(
            <RoutedOrganizationPanel
                bill={mocks.pageProps.current.bill as { id: number; organizations: (typeof organization)[] }}
            />,
        );
        readdOrganization();
    });

    it("restores edited support and summary after the selected chip removes and re-adds the organization", () => {
        setupPage();
        const view = renderRoutedPanel();

        editCurrentPosition();
        fireEvent.click(screen.getByRole("button", { name: "Remove Taco Org" }));
        completeRemoval();

        expect(screen.queryByLabelText("Taco Org position summary")).not.toBeInTheDocument();
        mocks.pageProps.current.bill = { id: 1, organizations: [] };
        view.rerender(
            <RoutedOrganizationPanel
                bill={mocks.pageProps.current.bill as { id: number; organizations: (typeof organization)[] }}
            />,
        );
        readdOrganization();
    });

    it("drops removed drafts when the bill changes", () => {
        setupPage();
        const view = renderRoutedPanel();

        editCurrentPosition();
        fireEvent.click(screen.getByRole("button", { name: "Remove Taco Org" }));
        completeRemoval();

        mocks.pageProps.current.bill = { id: 2, organizations: [] };
        view.rerender(
            <RoutedOrganizationPanel
                bill={mocks.pageProps.current.bill as { id: number; organizations: (typeof organization)[] }}
            />,
        );
        mocks.pageProps.current.bill = { id: 1, organizations: [] };
        view.rerender(
            <RoutedOrganizationPanel
                bill={mocks.pageProps.current.bill as { id: number; organizations: (typeof organization)[] }}
            />,
        );

        const picker = screen.getByPlaceholderText("Search or create an organization...");
        fireEvent.change(picker, { target: { value: "Taco Org" } });
        fireEvent.click(screen.getByRole("button", { name: "Taco Org" }));

        expect(screen.getByLabelText("Taco Org position summary")).toHaveValue("");
        expect(screen.getByRole("switch", { name: "Taco Org support" })).toHaveAttribute("aria-checked", "true");
    });
});
