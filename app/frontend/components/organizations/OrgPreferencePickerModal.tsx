// @lat: [[org-notification-cascade-and-defaults#Why OrgPreferencePickerModal's create mode POSTs instead of PATCHing]]

import { useForm } from "@inertiajs/react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";
import { Alert, AlertDescription } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import { Checkbox } from "app/frontend/components/ui/checkbox";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "app/frontend/components/ui/dialog";
import { Label } from "app/frontend/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Separator } from "app/frontend/components/ui/separator";
import { sway } from "sway";

interface IProps {
    organization: sway.IPublicOrganization;
    followId: number;
    isFirstFollow?: boolean;
    // @lat: [[org-notification-cascade-and-defaults#Why OrgPreferencePickerModal's create mode POSTs instead of PATCHing]]
    createMode?: boolean;
    masterEnabled: boolean;
    open: boolean;
    onClose: () => void;
    initialNotifyOnNewPosition?: boolean;
    initialNotifyOnSupportChange?: boolean;
    initialNotifyOnSummaryChange?: boolean;
    initialCadence?: string;
}

const OrgPreferencePickerModal: React.FC<IProps> = ({
    organization,
    followId,
    isFirstFollow = false,
    createMode = false,
    masterEnabled,
    open,
    onClose,
    initialNotifyOnNewPosition = true,
    initialNotifyOnSupportChange = true,
    initialNotifyOnSummaryChange = true,
    initialCadence = "every_change",
}) => {
    const { data, setData, post, patch, processing } = useForm({
        organization_id: organization.id,
        organization_follow: {
            notify_on_new_position: Boolean(initialNotifyOnNewPosition),
            notify_on_support_change: Boolean(initialNotifyOnSupportChange),
            notify_on_summary_change: Boolean(initialNotifyOnSummaryChange),
            notification_cadence: initialCadence,
        },
    });

    const save = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (createMode) {
            // @lat: [[org-notification-cascade-and-defaults#Why OrgPreferencePickerModal's create mode POSTs instead of PATCHing]]
            post(ROUTES.organizationFollows, {
                preserveScroll: true,
                onSuccess: () => onClose(),
            });
        } else {
            patch(ROUTES.organizationFollowPreferences(followId), {
                preserveScroll: true,
                onSuccess: () => onClose(),
            });
        }
    };

    return (
        <Dialog open={open} onOpenChange={(isOpen) => !isOpen && onClose()}>
            <DialogContent className="sm:max-w-md">
                <DialogHeader>
                    <DialogTitle>{PARITY_COPY.orgNotifications.prefsTitle}</DialogTitle>
                    <p className="text-sm text-muted-foreground">
                        {PARITY_COPY.orgNotifications.prefsSubtitle(organization.name)}
                    </p>
                </DialogHeader>

                <form onSubmit={save} className="space-y-4">
                    <div className="space-y-3">
                        <p className="text-xs font-semibold tracking-widest uppercase text-muted-foreground">
                            Notify me about:
                        </p>

                        <div className="flex items-center gap-3">
                            <Checkbox
                                id="pref-new-position"
                                checked={data.organization_follow.notify_on_new_position}
                                onCheckedChange={(checked) =>
                                    setData("organization_follow", {
                                        ...data.organization_follow,
                                        notify_on_new_position: Boolean(checked),
                                    })
                                }
                            />
                            <Label htmlFor="pref-new-position" className="text-sm font-semibold">
                                {PARITY_COPY.orgNotifications.eventNewPosition}
                            </Label>
                        </div>

                        <div className="flex items-center gap-3">
                            <Checkbox
                                id="pref-support-change"
                                checked={data.organization_follow.notify_on_support_change}
                                onCheckedChange={(checked) =>
                                    setData("organization_follow", {
                                        ...data.organization_follow,
                                        notify_on_support_change: Boolean(checked),
                                    })
                                }
                            />
                            <Label htmlFor="pref-support-change" className="text-sm font-semibold">
                                {PARITY_COPY.orgNotifications.eventSupportChange}
                            </Label>
                        </div>

                        <div className="flex items-center gap-3">
                            <Checkbox
                                id="pref-summary-change"
                                checked={data.organization_follow.notify_on_summary_change}
                                onCheckedChange={(checked) =>
                                    setData("organization_follow", {
                                        ...data.organization_follow,
                                        notify_on_summary_change: Boolean(checked),
                                    })
                                }
                            />
                            <Label htmlFor="pref-summary-change" className="text-sm font-semibold">
                                {PARITY_COPY.orgNotifications.eventSummaryChange}
                            </Label>
                        </div>
                    </div>

                    <Separator />

                    <div className="space-y-3">
                        <p className="text-xs font-semibold tracking-widest uppercase text-muted-foreground">
                            How often:
                        </p>
                        <Select
                            value={data.organization_follow.notification_cadence}
                            onValueChange={(value) =>
                                setData("organization_follow", {
                                    ...data.organization_follow,
                                    notification_cadence: value,
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
                                <SelectItem value="daily">{PARITY_COPY.orgNotifications.cadenceDaily}</SelectItem>
                                <SelectItem value="weekly">{PARITY_COPY.orgNotifications.cadenceWeekly}</SelectItem>
                            </SelectContent>
                        </Select>
                    </div>

                    {!masterEnabled && (
                        <Alert variant="warning">
                            <AlertDescription>
                                Your global org-notification master switch is off. These preferences are saved but no
                                notifications will be sent until you turn it on in Notifications settings.
                            </AlertDescription>
                        </Alert>
                    )}

                    <DialogFooter>
                        {isFirstFollow && (
                            <Button type="button" variant="outline" onClick={onClose} disabled={processing}>
                                {PARITY_COPY.orgNotifications.skipForNow}
                            </Button>
                        )}
                        <Button type="submit" variant="default" disabled={processing}>
                            {PARITY_COPY.orgNotifications.savePreferences}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    );
};

export default OrgPreferencePickerModal;
