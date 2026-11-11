import { router } from "@inertiajs/react";
import {
    ICreatorOrganizations,
    TOrganizationError,
    TOrganizationOption,
} from "app/frontend/components/admin/creator/types";
import { Support } from "app/frontend/sway_constants";
import { notify, titleize } from "app/frontend/sway_utils";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";
import { Check, Pencil, Trash2, X } from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { Switch } from "app/frontend/components/ui/switch";
import { Textarea } from "app/frontend/components/ui/textarea";
import { useSwayFormContext } from "app/frontend/components/admin/creator/context/useSwayFormContext";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import OrgIconUpload from "app/frontend/components/admin/creator/OrgIconUpload";

interface IProps {
    index: number;
    organization: TOrganizationOption;
    error?: TOrganizationError;
    // @lat: [[bill-creator-organization-form#A separate form submits organization edits]]
    billId: number;
    tabKey: string;
    removing: boolean;
    onRemove: () => void;
}

// @lat: [[bill-creator-organization-form#A separate form submits organization edits]]
const BillCreatorOrganization: React.FC<IProps> = ({
    index,
    organization,
    error,
    billId,
    tabKey,
    removing,
    onRemove,
}) => {
    const { setData } = useSwayFormContext<ICreatorOrganizations>();

    const support = organization.support ?? Support.For;
    const summary = organization.summary ?? "";
    const iconUrl = organization.icon_url ?? "";

    const isSupport = support === Support.For;

    // @lat: [[bill-creator-organization-form#Rename updates the saved organization and current form]]
    const canRename = typeof organization.value === "number" && organization.value > 0;
    const [editingName, setEditingName] = useState<boolean>(false);
    const [nameDraft, setNameDraft] = useState<string>(organization.label);
    const [renaming, setRenaming] = useState<boolean>(false);

    const onStartRename = useCallback(() => {
        setNameDraft(organization.label);
        setEditingName(true);
    }, [organization.label]);

    const onCancelRename = useCallback(() => {
        setNameDraft(organization.label);
        setEditingName(false);
    }, [organization.label]);

    const onSaveRename = useCallback(() => {
        const next = nameDraft.trim();
        if (!next || next === organization.label) {
            setEditingName(false);
            return;
        }
        setRenaming(true);
        // @lat: [[bill-creator-organization-form#Rename updates the saved organization and current form]]
        router.patch(
            `/organizations/${organization.value}`,
            { name: next, bill_id: billId, bill_creator_tab: tabKey },
            {
                preserveScroll: true,
                // @lat: [[identity-and-access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]
                onSuccess: (page) => {
                    const flashAlert = (page as { props?: { flash?: { alert?: unknown } } } | undefined)?.props?.flash
                        ?.alert;
                    if (pageExpired(page) || flashAlert) return;
                    setData(`organizations.${index}.label` as keyof ICreatorOrganizations, next as never);
                    setEditingName(false);
                },
                onFinish: () => setRenaming(false),
            },
        );
    }, [nameDraft, organization.label, organization.value, billId, tabKey, index, setData]);

    const onToggleSupport = useCallback(
        (checked: boolean) => {
            setData(
                `organizations.${index}.support` as keyof ICreatorOrganizations,
                (checked ? Support.For : Support.Against) as never,
            );
        },
        [index, setData],
    );

    const onChangeSummary = useCallback(
        (e: React.ChangeEvent<HTMLTextAreaElement>) => {
            setData(`organizations.${index}.summary` as keyof ICreatorOrganizations, e.target.value as never);
        },
        [index, setData],
    );

    const onIconUploaded = useCallback(
        ({ signedId, previewUrl }: { signedId: string; previewUrl: string }) => {
            if (iconUrl.startsWith("blob:") && iconUrl !== previewUrl) {
                URL.revokeObjectURL(iconUrl);
            }
            setData(`organizations.${index}.icon_signed_id` as keyof ICreatorOrganizations, signedId as never);
            setData(`organizations.${index}.icon_url` as keyof ICreatorOrganizations, previewUrl as never);
            notify({ level: "success", title: "Icon uploaded." });
        },
        [iconUrl, index, setData],
    );

    const onIconRemove = useCallback(() => {
        if (iconUrl.startsWith("blob:")) {
            URL.revokeObjectURL(iconUrl);
        }
        setData(`organizations.${index}.icon_signed_id` as keyof ICreatorOrganizations, "" as never);
        setData(`organizations.${index}.icon_url` as keyof ICreatorOrganizations, "" as never);
    }, [iconUrl, index, setData]);

    const supportLabel = useMemo(() => {
        if (support === Support.Abstain) return titleize(Support.Abstain);
        return titleize(isSupport ? Support.For : Support.Against);
    }, [isSupport, support]);

    return (
        <div className="rounded-lg border-neo border-border-strong bg-card p-4 shadow-neo">
            <div className="flex flex-wrap items-start justify-between gap-3">
                {editingName ? (
                    <div className="flex flex-1 flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center">
                        <Input
                            value={nameDraft}
                            onChange={(e) => setNameDraft(e.target.value)}
                            aria-label="Organization name"
                            data-testid={`input-rename-org-${index}`}
                            className="w-full sm:max-w-xs"
                        />
                        <div className="flex items-center gap-2">
                            <Button
                                type="button"
                                variant="default"
                                size="sm"
                                disabled={renaming}
                                onClick={onSaveRename}
                                data-testid={`btn-save-rename-org-${index}`}
                            >
                                <Check aria-hidden />
                                &nbsp;{renaming ? "Saving…" : "Save name"}
                            </Button>
                            <Button type="button" variant="ghost" size="sm" onClick={onCancelRename}>
                                <X aria-hidden />
                                &nbsp;Cancel
                            </Button>
                        </div>
                    </div>
                ) : (
                    <div className="flex items-center gap-2">
                        <h3 className="text-lg font-semibold">{organization.label}</h3>
                        {canRename && (
                            <>
                                <Button
                                    type="button"
                                    variant="ghost"
                                    size="sm"
                                    onClick={onStartRename}
                                    data-testid={`btn-rename-org-${index}`}
                                    title="Rename this organization. Applies to every bill in this locale."
                                    className="min-h-[44px] sm:min-h-8"
                                >
                                    <Pencil aria-hidden />
                                    &nbsp;Rename
                                </Button>
                                <FeatureInfo note="creator.orgRename" />
                            </>
                        )}
                    </div>
                )}
                <div className="flex items-center gap-1.5">
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        disabled={removing}
                        onClick={onRemove}
                        data-testid={`btn-remove-org-${index}`}
                        className="min-h-[44px] sm:min-h-9"
                    >
                        <Trash2 aria-hidden />
                        &nbsp;{removing ? "Removing…" : "Remove organization"}
                    </Button>
                    <FeatureInfo note="creator.orgRemove" />
                </div>
            </div>
            {error?.label && <p className="mt-1 text-sm text-destructive">{error.label}</p>}

            <div className="mt-4 grid grid-cols-1 gap-6 md:grid-cols-2">
                <div className="flex flex-col gap-2">
                    <Label className="font-semibold" htmlFor={`organizations-${index}-support`}>
                        Position
                    </Label>
                    <Label
                        htmlFor={`organizations-${index}-support`}
                        className="flex min-h-11 cursor-pointer items-center gap-3"
                    >
                        <Switch
                            id={`organizations-${index}-support`}
                            checked={isSupport}
                            onCheckedChange={onToggleSupport}
                            aria-label={`${organization.label} support`}
                        />
                        <span className="text-sm font-semibold tracking-wide">{supportLabel}</span>
                        <FeatureInfo note="creator.orgPositionSwitch" />
                    </Label>
                    {error?.support && <p className="text-sm text-destructive">{error.support}</p>}
                </div>

                <div className="flex flex-col gap-2">
                    <Label className="font-semibold">Icon</Label>
                    <OrgIconUpload
                        label={organization.label}
                        iconUrl={iconUrl || null}
                        onUploaded={onIconUploaded}
                        onRemove={iconUrl ? onIconRemove : undefined}
                    />
                    {error?.icon_url && <p className="text-sm text-destructive">{error.icon_url}</p>}
                </div>
            </div>

            <div className="mt-6 flex flex-col gap-2">
                <div className="flex items-center gap-1.5">
                    <Label className="font-semibold" htmlFor={`organizations-${index}-summary`}>
                        {organization.label} position summary
                    </Label>
                    <FeatureInfo note="creator.orgPositionSummary" />
                </div>
                <Textarea
                    id={`organizations-${index}-summary`}
                    name={`organizations.${index}.summary`}
                    value={summary}
                    onChange={onChangeSummary}
                    rows={6}
                    aria-invalid={error?.summary ? true : undefined}
                />
                <p className="text-xs text-muted-foreground">
                    {organization.label}&rsquo;s opinion of the bill (markdown supported).
                </p>
                {error?.summary && <p className="text-sm text-destructive">{error.summary}</p>}
            </div>
        </div>
    );
};

export default BillCreatorOrganization;
