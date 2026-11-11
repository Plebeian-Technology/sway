import { useForm, usePage } from "@inertiajs/react";
import {
    ICreatorOrganizations,
    IOrganizationErrors,
    TOrganizationError,
    TOrganizationOption,
} from "app/frontend/components/admin/creator/types";
import { useTempStorage } from "app/frontend/components/admin/creator/hooks/useTempStorage";
import { Support } from "app/frontend/sway_constants";
import { notify, SWAY_STORAGE } from "app/frontend/sway_utils";
import { uniqueStableKeys } from "app/frontend/sway_utils/uniqueStableKeys";
import { Save } from "lucide-react";
import { Fragment, useCallback, useContext, useLayoutEffect, useMemo, useRef } from "react";
import { sway } from "sway";
import { Button } from "app/frontend/components/ui/button";
import BillCreatorFormHeader from "app/frontend/components/admin/creator/BillCreatorFormHeader";
import BillCreatorOrganization from "app/frontend/components/admin/creator/BillCreatorOrganization";
import BillCreatorOrgCombobox from "app/frontend/components/admin/creator/organizations/BillCreatorOrgCombobox";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";
import { useSwayFormContext } from "app/frontend/components/admin/creator/context/useSwayFormContext";
import { useRemoveOrgPosition } from "app/frontend/components/admin/creator/hooks/useRemoveOrgPosition";
import { BillCreatorOrganizationDraftCacheContext } from "app/frontend/components/admin/creator/context/BillCreatorOrganizationDraftCacheContext";

const toCreatorOption = (
    organization: sway.IOrganization,
    bill_id: number,
    includePositionId = true,
): TOrganizationOption => {
    const position = organization.positions?.find((p) => p.bill_id === bill_id);
    return {
        value: organization.id,
        label: organization.name,
        summary: position?.summary ?? "",
        support: (position?.support as TOrganizationOption["support"]) ?? Support.For,
        icon_url: organization.icon_url,
        // @lat: [[organization-position-removal#The button only reaches the server for a position that exists]]
        position_id: includePositionId ? position?.id : undefined,
    };
};

interface IPageProps {
    bill?: sway.IBill & { organizations?: sway.IOrganization[] };
    tab_key?: string;
    organizations?: sway.IOrganization[];
    [key: string]: unknown;
}

interface IProps {
    setCreatorDirty?: React.Dispatch<React.SetStateAction<boolean>>;
}

const OrganizationDirtySync: React.FC<IProps> = ({ setCreatorDirty }) => {
    const { isDirty } = useSwayFormContext<ICreatorOrganizations>();

    useLayoutEffect(() => {
        setCreatorDirty?.(Boolean(isDirty));
    }, [isDirty, setCreatorDirty]);

    useLayoutEffect(() => {
        return () => setCreatorDirty?.(false);
    }, [setCreatorDirty]);

    return null;
};

// @lat: [[bill-creator-organization-form#A separate form submits organization edits]]
const BillCreatorOrganizations: React.FC<IProps> = ({ setCreatorDirty }) => {
    const page = usePage<IPageProps>();
    const errors = (page.props.errors ?? {}) as Partial<IOrganizationErrors>;
    const bill = page.props.bill;
    // @lat: [[bill-creator-organization-form#A separate form submits organization edits]]
    const tabKey = page.props.tab_key ?? "positions";
    const organizationsProp = useMemo(() => page.props.organizations ?? [], [page.props.organizations]);

    const billId = bill?.id ?? 0;
    const billOrganizations = useMemo(
        () => (bill?.organizations ?? []).map((o) => toCreatorOption(o, billId)),
        [bill?.organizations, billId],
    );

    const initialValues = useMemo<ICreatorOrganizations>(
        () => ({ bill_id: billId, organizations: billOrganizations }),
        [billId, billOrganizations],
    );

    const form = useForm<ICreatorOrganizations>(initialValues);
    const { data, setData, post, processing } = form;
    const isDirty = form.isDirty ?? JSON.stringify(data) !== JSON.stringify(initialValues);
    const formContextValue = useMemo(() => ({ ...form, isDirty }), [form, isDirty]);

    const { storage, blurredFieldName } = useTempStorage(SWAY_STORAGE.Local.BillCreator.Organizations, data);

    const selected = useMemo(() => (data.organizations ?? []) as TOrganizationOption[], [data.organizations]);

    // @lat: [[bill-creator-organization-form#New rows and stable row keys]]
    const rowKeys = useMemo(() => uniqueStableKeys(selected.map((o) => `org-row-${o.value}`)), [selected]);

    const availableOptions = useMemo(
        () => organizationsProp.map((o) => toCreatorOption(o, billId, false)),
        [organizationsProp, billId],
    );

    // @lat: [[bill-creator-organization-form#New rows and stable row keys]]
    const localSessionCacheRef = useRef<Map<number | string, TOrganizationOption>>(new Map());
    const sessionCache = useContext(BillCreatorOrganizationDraftCacheContext) ?? localSessionCacheRef.current;

    const { removing, removePosition } = useRemoveOrgPosition(tabKey);

    const appendOrganization = useCallback(
        (option: TOrganizationOption) => {
            const cached = sessionCache.get(option.value);
            const next = [...selected, cached ?? option];
            setData("organizations", next);
        },
        [selected, sessionCache, setData],
    );

    const removeSelected = useCallback(
        (value: number | string) => {
            const removed = selected.find((o) => o.value === value);
            if (removed) sessionCache.set(removed.value, { ...removed, position_id: undefined });
            // @lat: [[organization-position-removal#Both remove controls go through the same request]]
            removePosition(removed?.position_id, () => {
                setData(
                    "organizations",
                    selected.filter((o) => o.value !== value),
                );
            });
        },
        [selected, sessionCache, setData, removePosition],
    );

    const onSubmit = useCallback(
        (e: React.SubmitEvent<HTMLFormElement>) => {
            e.preventDefault();

            if (!billId) {
                notify({
                    level: "error",
                    title: "Click Save on the Details and Summary tab before clicking save here.",
                });
                return;
            }

            post(`/organizations?bill_creator_tab=${encodeURIComponent(tabKey)}`, {
                preserveScroll: true,
                async: false,
            });
        },
        [billId, post, tabKey],
    );

    const orgErrors = errors.organizations as TOrganizationError[] | undefined;

    return (
        <SwayFormContext.Provider value={formContextValue}>
            <OrganizationDirtySync setCreatorDirty={setCreatorDirty} />
            <form onSubmit={onSubmit} className="flex flex-col gap-6 py-4">
                <BillCreatorFormHeader storage={storage} blurredFieldName={blurredFieldName} processing={processing} />

                <div className="flex flex-col gap-2">
                    <div className="flex items-center gap-1.5">
                        <h4 className="text-base font-medium">Organizations (optional)</h4>
                        <FeatureInfo note="creator.orgCombobox" />
                    </div>
                    <BillCreatorOrgCombobox
                        selected={selected}
                        availableOptions={availableOptions}
                        onAppend={appendOrganization}
                        onRemove={removeSelected}
                    />
                    <p className="text-xs text-muted-foreground">
                        Add an existing organization from this locale, or type a name and press Enter to create a new
                        one inline. Each selected organization appears below with its own sub-form.
                    </p>
                </div>

                <div className="flex flex-col gap-4">
                    {selected.length === 0 ? (
                        <p className="italic text-sm text-muted-foreground">
                            No organizations selected yet &mdash; add one above.
                        </p>
                    ) : (
                        selected.map((organization, index) => (
                            // @lat: [[bill-creator-organization-form#New rows and stable row keys]]
                            <Fragment key={`${rowKeys[index]}-${organization.value}`}>
                                <BillCreatorOrganization
                                    index={index}
                                    organization={organization}
                                    error={orgErrors?.[index]}
                                    billId={billId}
                                    tabKey={tabKey}
                                    removing={removing}
                                    onRemove={() => removeSelected(organization.value)}
                                />
                            </Fragment>
                        ))
                    )}
                </div>

                <div className="mt-4">
                    <Button
                        type="submit"
                        size="lg"
                        disabled={processing}
                        className="min-h-11 h-auto w-full sm:w-auto whitespace-normal py-2.5"
                    >
                        <Save aria-hidden />
                        &nbsp;Save Supporting/Opposing Arguments
                    </Button>
                </div>
            </form>
        </SwayFormContext.Provider>
    );
};

export default BillCreatorOrganizations;
