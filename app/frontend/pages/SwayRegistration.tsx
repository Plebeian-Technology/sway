// @lat: [[registration-dead-ends#Browser page state selectors]]

import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useForm, type InertiaFormProps } from "@inertiajs/react";
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
    typed_address?: string;
    is_voter_registration_address_confirmed: boolean;
    confirm_deactivate_legislators?: boolean;
}

interface IProps {
    user: sway.IUser;
    registration_outcome?: { reason: string; message: string } | null;
    sway_locale?: sway.ISwayLocale | null;
    locale?: sway.ISwayLocale | null;
    change_address?: boolean;
    current_address?: string | null;
}

const SwayRegistration: React.FC<IProps> = ({
    user,
    registration_outcome,
    sway_locale,
    locale,
    change_address = false,
    current_address,
}) => {
    const activeLocale = locale ?? sway_locale ?? null;
    const logout = useLogout();
    const hasAddressNotLocatedOutcome = registration_outcome?.reason === "address_not_located";
    const requiresAddressSwitchConfirmation =
        (Boolean(user?.is_registration_complete) || change_address) && !hasAddressNotLocatedOutcome;
    const form = useForm<IRegistrationFormData>({
        is_voter_registration_address_confirmed: false,
        ...(requiresAddressSwitchConfirmation ? { confirm_deactivate_legislators: false } : {}),
    } as IRegistrationFormData);
    const [isLoading, setLoading] = useState<boolean>(false);
    const [showSwitchConfirm, setShowSwitchConfirm] = useState<boolean>(false);
    const loadingToastId = useRef<string | undefined>(undefined);
    const noRepresentativesNotice =
        registration_outcome?.reason === "no_representatives" ? (
            <div data-testid="no-representatives-message" role="alert">
                <p className="text-sm text-muted-foreground">{registration_outcome.message}</p>
            </div>
        ) : null;
    // @lat: [[registration-dead-ends#Submitting the typed address when no complete suggestion is picked#Asking for a city or ZIP when the address cannot be located]]
    const addressNotLocatedNotice = hasAddressNotLocatedOutcome ? (
        <div
            data-testid="address-not-located-message"
            // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role lat:ignore
            role="status"
            className="space-y-2"
        >
            <p className="text-sm text-muted-foreground">{registration_outcome.message}</p>
            <Button asChild variant="outline">
                <Link href={ROUTES.feed} data-testid="link-continue-to-feed">
                    {PARITY_COPY.address.notLocated.continueCta}
                </Link>
            </Button>
        </div>
    ) : null;

    const handleStart = useCallback(() => {
        setLoading(true);
        loadingToastId.current = notify({
            level: "info",
            title: "Finding your representatives.",
            message: "Matching your address to your local and congressional legislators may take a minute...",
            duration: 0,
        });
    }, []);

    // @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
    const handleFinish = useCallback(() => {
        toast.dismiss(loadingToastId.current);
        setLoading(false);
    }, []);

    // @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
    const handleRequestFailed = useCallback(() => {
        notify({ level: "error", title: PARITY_COPY.address.requestFailed });
        return false;
    }, []);

    // @lat: [[web-profile-page#Web profile page#Changing the address from the web]]
    useEffect(() => {
        if (!change_address) {
            trackFunnelStepOnce("address_form_viewed");
        }
    }, [change_address]);

    useEffect(() => {
        if (!change_address && user?.is_registration_complete) {
            trackFunnelStepOnce("registration_completed");
        }
    }, [change_address, user?.is_registration_complete]);

    // @lat: [[registration-dead-ends#Submitting the typed address when no complete suggestion is picked]]
    const submitRegistration = useCallback(
        (extraData: Partial<IRegistrationFormData> = {}) => {
            if (!change_address) {
                trackFunnelStep("address_submitted", {
                    voter_confirmed: form.data.is_voter_registration_address_confirmed,
                    city: form.data.city,
                    region_code: form.data.region_code,
                });
            }
            handleStart();
            form.transform(({ typed_address, ...data }) => ({
                ...data,
                ...(data.street?.trim() || !typed_address?.trim() ? {} : { street: typed_address.trim() }),
                ...extraData,
            }));
            form.post("/sway_registration", {
                onHttpException: handleRequestFailed,
                onNetworkError: handleRequestFailed,
                onFinish: handleFinish,
            });
        },
        [change_address, form, handleStart, handleRequestFailed, handleFinish],
    );

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
        setShowSwitchConfirm(false);
        submitRegistration({ confirm_deactivate_legislators: true });
    }, [form, submitRegistration]);

    const handleOpenUrl = useCallback((url: string) => {
        window.open(url, "_blank", "noopener,noreferrer");
    }, []);

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
            {addressNotLocatedNotice}
            {/* @lat: [[web-profile-page#Web profile page#Changing the address from the web]] */}
            {change_address ? (
                <div className="space-y-1">
                    <h1 className="text-2xl font-semibold tracking-tight">{PARITY_COPY.profile.rows.address}</h1>
                    <p className="text-sm text-muted-foreground">{PARITY_COPY.address.switchConfirm.editLead}</p>
                    {current_address && (
                        <p className="text-sm text-foreground" data-testid="current-address">
                            <span className="font-semibold">{PARITY_COPY.address.edit.currentLabel}</span>{" "}
                            {current_address}
                        </p>
                    )}
                </div>
            ) : (
                <div className="space-y-1">
                    <h1 className="text-2xl font-semibold tracking-tight">{PARITY_COPY.address.complete.heading}</h1>
                    <p className="text-sm text-muted-foreground">{PARITY_COPY.address.complete.lead}</p>
                </div>
            )}

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
                            {change_address ? (
                                <Button asChild variant="outline">
                                    <Link href={ROUTES.profile}>{PARITY_COPY.address.edit.cancelCta}</Link>
                                </Button>
                            ) : (
                                <Button
                                    type="button"
                                    variant="outline"
                                    onClick={logout}
                                    data-testid="btn-cancel-registration"
                                >
                                    {PARITY_COPY.address.complete.cancelCta}
                                </Button>
                            )}
                            <Button type="submit" disabled={isLoading} data-testid="btn-submit-registration">
                                {change_address ? PARITY_COPY.address.edit.saveCta : PARITY_COPY.address.complete.cta}
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
