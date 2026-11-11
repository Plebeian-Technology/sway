// @lat: [[registration-dead-ends#Browser page state selectors]]

import { useCallback, useEffect, useState } from "react";
import { Link, usePoll, useForm, type InertiaFormProps } from "@inertiajs/react";
import { ExternalLink } from "lucide-react";
import toast from "react-hot-toast";
import { sway } from "sway";

import { useLogout } from "app/frontend/hooks/users/useLogout";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import NominatimAddressAutocomplete from "app/frontend/components/user/NominatimAddressAutocomplete";
import { notify } from "app/frontend/sway_utils";
import { trackFunnelStep, trackFunnelStepOnce } from "app/frontend/sway_utils/funnelTracker";

import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Checkbox } from "app/frontend/components/ui/checkbox";
import { Label } from "app/frontend/components/ui/label";
import { Separator } from "app/frontend/components/ui/separator";

const REGISTRATION_FIELD: sway.IFormField<sway.IUser> = {
    name: "address",
    component: "text",
    type: "text",
    label: "Address",
    isRequired: true,
    autoComplete: "shipping address",
};

interface IRegistrationFormData extends sway.IAddress {
    is_voter_registration_address_confirmed: boolean;
    confirm_deactivate_legislators?: boolean;
}

interface IProps {
    user: sway.IUser;
    processing?: boolean;
    registration_outcome?: { reason: string; message: string } | null;
    sway_locale?: sway.ISwayLocale | null;
    locale?: sway.ISwayLocale | null;
}

const SwayRegistration: React.FC<IProps> = ({ user, processing, registration_outcome, sway_locale, locale }) => {
    const activeLocale = locale ?? sway_locale ?? null;
    const logout = useLogout();
    const requiresAddressSwitchConfirmation = Boolean(user?.is_registration_complete || user?.address);
    const form = useForm<IRegistrationFormData>({
        is_voter_registration_address_confirmed: false,
        ...(requiresAddressSwitchConfirmation ? { confirm_deactivate_legislators: false } : {}),
    } as IRegistrationFormData);
    const [isLoading, setLoading] = useState<boolean>(false);
    const [isCorrectingAddress, setCorrectingAddress] = useState<boolean>(false);
    const [showSwitchConfirm, setShowSwitchConfirm] = useState<boolean>(false);
    const noRepresentativesNotice =
        registration_outcome?.reason === "no_representatives" ? (
            <div data-testid="no-representatives-message" role="alert">
                <p className="text-sm text-muted-foreground">{registration_outcome.message}</p>
            </div>
        ) : null;
    const hasNoRepresentativesOutcome = registration_outcome?.reason === "no_representatives";

    const handleStart = useCallback(() => {
        setLoading(true);
        notify({
            level: "info",
            title: "Finding your representatives.",
            message: "Matching your address to your local and congressional legislators may take a minute...",
            duration: 0,
        });
    }, []);

    // @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
    const handleFinish = useCallback(() => {
        toast.dismiss();
        setLoading(false);
        setCorrectingAddress(false);
    }, []);

    useEffect(() => {
        trackFunnelStepOnce("address_form_viewed");
    }, []);

    useEffect(() => {
        if (processing) {
            trackFunnelStepOnce("geocode_polling_started");
        }
    }, [processing]);

    useEffect(() => {
        if (user?.is_registration_complete) {
            trackFunnelStepOnce("registration_completed");
        } else if (user?.registration_status === "failed") {
            trackFunnelStepOnce("registration_failed");
        }
    }, [user?.is_registration_complete, user?.registration_status]);

    const submitRegistration = useCallback(() => {
        trackFunnelStep("address_submitted", {
            voter_confirmed: form.data.is_voter_registration_address_confirmed,
            city: form.data.city,
            region_code: form.data.region_code,
        });
        handleStart();
        form.post("/sway_registration", { onFinish: handleFinish });
    }, [form, handleStart, handleFinish]);

    const handleSubmit = useCallback(
        (e: React.SubmitEvent<HTMLFormElement>) => {
            e.preventDefault();
            if (requiresAddressSwitchConfirmation && !form.data.confirm_deactivate_legislators) {
                setShowSwitchConfirm(true);
                return;
            }
            submitRegistration();
        },
        [requiresAddressSwitchConfirmation, form.data.confirm_deactivate_legislators, submitRegistration],
    );

    const handleConfirmAddressSwitch = useCallback(() => {
        form.setData("confirm_deactivate_legislators", true);
        form.transform((data) => ({
            ...data,
            confirm_deactivate_legislators: true,
        }));
        setShowSwitchConfirm(false);
        submitRegistration();
    }, [form, submitRegistration]);

    const handleOpenUrl = useCallback((url: string) => {
        window.open(url, "_blank", "noopener,noreferrer");
    }, []);

    usePoll(3000, { only: ["user", "processing"] }, { autoStart: !!processing && !hasNoRepresentativesOutcome });

    if (processing && !hasNoRepresentativesOutcome) {
        return (
            <div className="mx-auto w-full max-w-2xl">
                <Card>
                    <CardHeader>
                        <CardTitle>{PARITY_COPY.address.processing.title}</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <output
                            data-testid="registration-processing"
                            aria-label="Registration in progress"
                            aria-live="polite"
                        >
                            <p data-testid="registration-processing-message" className="text-sm text-muted-foreground">
                                {PARITY_COPY.address.processing.message}
                            </p>
                        </output>
                    </CardContent>
                </Card>
            </div>
        );
    }

    if (user?.registration_status === "failed" && !isCorrectingAddress) {
        return (
            <div className="mx-auto w-full max-w-2xl">
                <Card>
                    <CardHeader>
                        <CardTitle>{PARITY_COPY.address.failed.title}</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        {noRepresentativesNotice}
                        <div data-testid="registration-error" role="alert">
                            <p className="text-sm text-muted-foreground">{PARITY_COPY.address.failed.message}</p>
                        </div>
                        {/* @lat: [[registration-dead-ends#Correcting an address after a failed lookup]] */}
                        <Button
                            type="button"
                            onClick={() => setCorrectingAddress(true)}
                            data-testid="btn-retry-registration"
                        >
                            {PARITY_COPY.address.failed.retryCta}
                        </Button>
                    </CardContent>
                </Card>
            </div>
        );
    }

    if (!user?.id) {
        return (
            <div className="mx-auto w-full max-w-2xl">
                <Card>
                    <CardHeader>
                        <CardTitle>{PARITY_COPY.address.sessionExpired.title}</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        <p className="text-sm text-muted-foreground">{PARITY_COPY.address.sessionExpired.message}</p>
                        {/* @lat: [[registration-dead-ends#Reaching sign-in from an expired session]] */}
                        <Button asChild data-testid="link-signin">
                            <Link href={ROUTES.signin}>{PARITY_COPY.address.sessionExpired.cta}</Link>
                        </Button>
                    </CardContent>
                </Card>
            </div>
        );
    }

    return (
        <div className="mx-auto w-full max-w-2xl space-y-6">
            {noRepresentativesNotice}
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">{PARITY_COPY.address.complete.heading}</h1>
                <p className="text-sm text-muted-foreground">{PARITY_COPY.address.complete.lead}</p>
            </div>

            <Card>
                <CardContent className="pt-6">
                    <form onSubmit={handleSubmit} className="space-y-4">
                        <NominatimAddressAutocomplete
                            form={form as unknown as InertiaFormProps<Record<string, unknown>>}
                            field={REGISTRATION_FIELD}
                            setLoading={setLoading}
                            locale={activeLocale}
                        />

                        <div className="flex items-start gap-3">
                            <Checkbox
                                id="registered-voter-address-confirmation"
                                data-testid="registered-voter-address-confirmation"
                                checked={form.data.is_voter_registration_address_confirmed}
                                onCheckedChange={(checked) =>
                                    form.setData("is_voter_registration_address_confirmed", checked === true)
                                }
                            />
                            <div className="grid gap-1 leading-none">
                                <Label htmlFor="registered-voter-address-confirmation">
                                    {PARITY_COPY.address.helper.registeredVoterConfirmation.label}
                                </Label>
                                <p className="text-sm text-muted-foreground">
                                    {PARITY_COPY.address.helper.registeredVoterConfirmation.description}
                                </p>
                            </div>
                        </div>

                        {showSwitchConfirm ? (
                            <div
                                data-testid="confirm-address-switch-dialog"
                                role="alert"
                                className="rounded-md border border-border bg-muted/40 p-4 space-y-3"
                            >
                                <p className="text-sm font-medium text-foreground">
                                    {PARITY_COPY.address.switchConfirm.title}
                                </p>
                                <p className="text-sm text-muted-foreground">
                                    {PARITY_COPY.address.switchConfirm.body}
                                </p>
                                <div className="flex flex-row items-center justify-end gap-3">
                                    <Button
                                        type="button"
                                        variant="outline"
                                        onClick={() => setShowSwitchConfirm(false)}
                                        data-testid="btn-cancel-address-switch"
                                    >
                                        {PARITY_COPY.address.switchConfirm.cancelCta}
                                    </Button>
                                    <Button
                                        type="button"
                                        disabled={isLoading}
                                        onClick={handleConfirmAddressSwitch}
                                        data-testid="btn-confirm-address-switch"
                                    >
                                        {PARITY_COPY.address.switchConfirm.confirmCta}
                                    </Button>
                                </div>
                            </div>
                        ) : null}

                        <div className="flex flex-row items-center justify-end gap-3 pt-2">
                            <Button
                                type="button"
                                variant="outline"
                                onClick={logout}
                                data-testid="btn-cancel-registration"
                            >
                                {PARITY_COPY.address.complete.cancelCta}
                            </Button>
                            <Button type="submit" disabled={isLoading} data-testid="btn-submit-registration">
                                {PARITY_COPY.address.complete.cta}
                            </Button>
                        </div>
                    </form>
                </CardContent>
            </Card>

            <Separator />

            <div className="space-y-4 text-sm text-muted-foreground">
                <p>{PARITY_COPY.address.helper.registeredVoterAdvisory}</p>
                <p>
                    If you are not registered to vote, it is not required by Sway, but is{" "}
                    <span className="font-semibold text-foreground">strongly</span> recommended.{" "}
                    <button
                        type="button"
                        onClick={() => handleOpenUrl(PARITY_COPY.address.helper.registerToVoteUrl)}
                        className="inline-flex items-center gap-1 font-semibold text-primary underline-offset-4 hover:underline"
                    >
                        {PARITY_COPY.address.helper.registerToVote}
                        <ExternalLink className="size-3.5" aria-hidden />
                    </button>
                </p>
                <p>
                    <button
                        type="button"
                        onClick={() => handleOpenUrl(PARITY_COPY.address.helper.checkRegistrationUrl)}
                        className="inline-flex items-center gap-1 font-semibold text-primary underline-offset-4 hover:underline"
                    >
                        {PARITY_COPY.address.helper.checkRegistration}
                        <ExternalLink className="size-3.5" aria-hidden />
                    </button>
                </p>
                <p>
                    {PARITY_COPY.address.helper.viewOnGitHubIntro}{" "}
                    <button
                        type="button"
                        onClick={() => handleOpenUrl(PARITY_COPY.address.helper.viewOnGitHubUrl)}
                        className="inline-flex items-center gap-1 font-semibold text-primary underline-offset-4 hover:underline"
                    >
                        {PARITY_COPY.address.helper.viewOnGitHub}
                        <ExternalLink className="size-3.5" aria-hidden />
                    </button>
                </p>
            </div>
        </div>
    );
};

export default SwayRegistration;
