import { Link } from "@inertiajs/react";
import { useEffect, useMemo } from "react";
import { Download } from "lucide-react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Checkbox } from "app/frontend/components/ui/checkbox";
import { Label } from "app/frontend/components/ui/label";
import { SMS_CONSENT_DISCLOSURE, SMS_CONSENT_LABEL } from "app/frontend/sway_constants/smsConsent";

interface IProps {
    enabled: boolean;
    sms_phone: string | null;
    // True renders every control disabled and never submits.
    preview?: boolean;
    canSubmit?: boolean;
    onEnabledChange?: (checked: boolean) => void;
    onSubmit?: (e: React.SubmitEvent<HTMLFormElement>) => void;
}

const buildVCard = (sms_phone: string) => {
    const phoneNumber = sms_phone.replace(/\D/g, "");
    const contactName = "Sway Notifications";
    const vCardContent = `BEGIN:VCARD
VERSION:3.0
FN:${contactName}
TEL;TYPE=CELL:${phoneNumber}
END:VCARD`;
    const blob = new Blob([vCardContent], { type: "text/vcard" });
    const downloadUrl = URL.createObjectURL(blob);
    const filename = `${contactName.replace(/\s/g, "_")}.vcf`;
    return { downloadUrl, filename };
};

const preventSubmit = (e: React.SubmitEvent<HTMLFormElement>) => e.preventDefault();

// @lat: [[public-disclosure-pages#Why /sms renders the live consent panel instead of a screenshot]]
const SmsNotificationsPanelView: React.FC<IProps> = ({
    enabled,
    sms_phone,
    preview = false,
    canSubmit = false,
    onEnabledChange,
    onSubmit,
}) => {
    const vCard = useMemo(() => (sms_phone ? buildVCard(sms_phone) : null), [sms_phone]);
    useEffect(
        () => () => {
            if (vCard) URL.revokeObjectURL(vCard.downloadUrl);
        },
        [vCard],
    );

    const checkboxId = preview ? "sms-notifications-enabled-preview" : "sms-notifications-enabled";

    return (
        <Card
            data-testid={preview ? "sms-consent-preview" : "notification-sms-toggle"}
            aria-live={preview ? undefined : "polite"}
        >
            <CardHeader>
                <div className="flex items-start justify-between gap-4">
                    <CardTitle className="text-lg">SMS notifications from Sway</CardTitle>
                    <Badge variant="stamp" tone={enabled ? "success" : "neutral"}>
                        {enabled ? "Enabled" : "Disabled"}
                    </Badge>
                </div>
            </CardHeader>
            <CardContent className="space-y-4">
                <p className="text-sm text-muted-foreground">
                    Sway can keep you informed about new Bills of the Month by sending you a text message whenever a new
                    one is released. Expect at most one to three messages per week.
                </p>

                <form onSubmit={preview ? preventSubmit : onSubmit} className="space-y-4">
                    <div className="flex items-start gap-3">
                        <Checkbox
                            id={checkboxId}
                            checked={enabled}
                            disabled={preview}
                            onCheckedChange={(checked) => onEnabledChange?.(Boolean(checked))}
                            className="mt-0.5"
                        />
                        <div className="space-y-2">
                            <Label htmlFor={checkboxId} className="text-sm font-semibold">
                                {SMS_CONSENT_LABEL}
                            </Label>
                            <p className="text-sm text-muted-foreground">{SMS_CONSENT_DISCLOSURE}</p>
                            <p className="text-sm text-muted-foreground">
                                <Link href="/privacy" className="underline">
                                    Privacy Policy
                                </Link>
                                {" · "}
                                <Link href="/terms" className="underline">
                                    Terms of Service
                                </Link>
                            </p>
                        </div>
                    </div>
                    <Button type="submit" variant="default" disabled={preview || !canSubmit}>
                        Save preferences
                    </Button>
                </form>

                <p className="text-sm text-muted-foreground">
                    If you ever opt out by mistake, reply <span className="font-semibold">START</span> to the Sway
                    number to opt back in. Reply <span className="font-semibold">STOP</span> at any time to opt out.
                </p>

                {sms_phone && vCard && (
                    <>
                        <p className="text-sm text-muted-foreground">
                            Sway's phone number is{" "}
                            <span className="font-semibold tabular-nums lining-nums text-foreground">{sms_phone}</span>.
                            Save it to your contacts as "Sway Notifications" using the download below.
                        </p>

                        <div>
                            <Button variant="outline" asChild>
                                <a href={vCard.downloadUrl} download={vCard.filename}>
                                    <Download /> Download Sway contact (.vcf)
                                </a>
                            </Button>
                        </div>
                    </>
                )}

                <p className="text-xs text-muted-foreground">
                    IMPORTANT: This number does not accept phone calls, and replies other than STOP, START and HELP are
                    not monitored. You may still be billed by your carrier if you call or message it. Message and data
                    rates may apply.
                </p>
            </CardContent>
        </Card>
    );
};

export default SmsNotificationsPanelView;
