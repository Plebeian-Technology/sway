import { useForm } from "@inertiajs/react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Checkbox } from "app/frontend/components/ui/checkbox";
import { Label } from "app/frontend/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Separator } from "app/frontend/components/ui/separator";
import { Switch } from "app/frontend/components/ui/switch";

interface IProps {
    org_position_taken?: boolean;
    org_position_cadence_default?: string;
    notify_on_new_position_default?: boolean;
    notify_on_support_change_default?: boolean;
    notify_on_summary_change_default?: boolean;
}

const OrganizationsNotificationsPanel: React.FC<IProps> = ({
    org_position_taken = false,
    org_position_cadence_default = "every_change",
    notify_on_new_position_default = true,
    notify_on_support_change_default = true,
    notify_on_summary_change_default = true,
}) => {
    const { data, setData, patch, processing } = useForm({
        user: {
            org_position_taken: Boolean(org_position_taken),
            org_position_cadence_default: org_position_cadence_default ?? "every_change",
            notify_on_new_position_default: Boolean(notify_on_new_position_default),
            notify_on_support_change_default: Boolean(notify_on_support_change_default),
            notify_on_summary_change_default: Boolean(notify_on_summary_change_default),
        },
    });

    const isDirty =
        data.user.org_position_taken !== Boolean(org_position_taken) ||
        data.user.org_position_cadence_default !== (org_position_cadence_default ?? "every_change") ||
        data.user.notify_on_new_position_default !== Boolean(notify_on_new_position_default) ||
        data.user.notify_on_support_change_default !== Boolean(notify_on_support_change_default) ||
        data.user.notify_on_summary_change_default !== Boolean(notify_on_summary_change_default);

    const submit = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        patch(ROUTES.notificationsOrgDefaults, {
            preserveScroll: true,
        });
    };

    // @lat: [[organization-follow-control#Following an organization#Why a switch and its badge read different sources]]
    const masterEnabled = data.user.org_position_taken;
    const savedMasterEnabled = Boolean(org_position_taken);

    return (
        <Card data-testid="notification-orgs-toggle" aria-live="polite">
            <CardHeader>
                <div className="flex items-start justify-between gap-4">
                    <CardTitle className="text-lg font-semibold">{PARITY_COPY.orgNotifications.panelTitle}</CardTitle>
                    <div className="flex items-center gap-2">
                        {isDirty && (
                            <span
                                className="text-xs font-semibold text-muted-foreground"
                                data-testid="org-notifications-unsaved"
                            >
                                Unsaved
                            </span>
                        )}
                        <Badge
                            variant="stamp"
                            tone={savedMasterEnabled ? "success" : "neutral"}
                            data-testid="org-notifications-saved-state"
                        >
                            {savedMasterEnabled ? "Enabled" : "Disabled"}
                        </Badge>
                    </div>
                </div>
            </CardHeader>
            <CardContent className="space-y-4">
                <p className="text-sm text-muted-foreground">{PARITY_COPY.orgNotifications.panelDescription}</p>

                <form onSubmit={submit} className="space-y-4">
                    <div className="flex items-center gap-3">
                        <Switch
                            id="org-position-master"
                            checked={masterEnabled}
                            onCheckedChange={(checked) =>
                                setData("user", {
                                    ...data.user,
                                    org_position_taken: Boolean(checked),
                                })
                            }
                        />
                        <Label htmlFor="org-position-master" className="text-sm font-semibold">
                            Enable organization notifications
                        </Label>
                    </div>

                    {masterEnabled && (
                        <>
                            <Separator />

                            <div className="space-y-3">
                                <p className="text-xs font-semibold tracking-widest uppercase text-muted-foreground">
                                    {PARITY_COPY.orgNotifications.defaultsEventsLabel}
                                </p>

                                <div className="flex items-center gap-3">
                                    <Checkbox
                                        id="org-notify-new-position"
                                        checked={data.user.notify_on_new_position_default}
                                        onCheckedChange={(checked) =>
                                            setData("user", {
                                                ...data.user,
                                                notify_on_new_position_default: Boolean(checked),
                                            })
                                        }
                                    />
                                    <Label htmlFor="org-notify-new-position" className="text-sm font-semibold">
                                        {PARITY_COPY.orgNotifications.eventNewPosition}
                                    </Label>
                                </div>

                                <div className="flex items-center gap-3">
                                    <Checkbox
                                        id="org-notify-support-change"
                                        checked={data.user.notify_on_support_change_default}
                                        onCheckedChange={(checked) =>
                                            setData("user", {
                                                ...data.user,
                                                notify_on_support_change_default: Boolean(checked),
                                            })
                                        }
                                    />
                                    <Label htmlFor="org-notify-support-change" className="text-sm font-semibold">
                                        {PARITY_COPY.orgNotifications.eventSupportChange}
                                    </Label>
                                </div>

                                <div className="flex items-center gap-3">
                                    <Checkbox
                                        id="org-notify-summary-change"
                                        checked={data.user.notify_on_summary_change_default}
                                        onCheckedChange={(checked) =>
                                            setData("user", {
                                                ...data.user,
                                                notify_on_summary_change_default: Boolean(checked),
                                            })
                                        }
                                    />
                                    <Label htmlFor="org-notify-summary-change" className="text-sm font-semibold">
                                        {PARITY_COPY.orgNotifications.eventSummaryChange}
                                    </Label>
                                </div>
                            </div>

                            <Separator />

                            <div className="space-y-3">
                                <p className="text-xs font-semibold tracking-widest uppercase text-muted-foreground">
                                    {PARITY_COPY.orgNotifications.defaultsCadenceLabel}
                                </p>
                                <Select
                                    value={data.user.org_position_cadence_default}
                                    onValueChange={(value) =>
                                        setData("user", {
                                            ...data.user,
                                            org_position_cadence_default: value,
                                        })
                                    }
                                >
                                    <SelectTrigger>
                                        <SelectValue placeholder="Select cadence" />
                                    </SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="every_change">
                                            {PARITY_COPY.orgNotifications.cadenceEveryChange}
                                        </SelectItem>
                                        <SelectItem value="daily">
                                            {PARITY_COPY.orgNotifications.cadenceDaily}
                                        </SelectItem>
                                        <SelectItem value="weekly">
                                            {PARITY_COPY.orgNotifications.cadenceWeekly}
                                        </SelectItem>
                                    </SelectContent>
                                </Select>
                            </div>
                        </>
                    )}

                    {!masterEnabled && (
                        <p className="text-sm text-muted-foreground">
                            Turn on organization notifications above to customize defaults.
                        </p>
                    )}

                    <Button
                        type="submit"
                        variant="default"
                        disabled={processing || !isDirty}
                        data-testid="org-notifications-save"
                    >
                        {PARITY_COPY.orgNotifications.savePreferences}
                    </Button>
                </form>
            </CardContent>
        </Card>
    );
};

export default OrganizationsNotificationsPanel;
