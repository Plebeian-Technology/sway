import { Link as InertiaLink, usePage } from "@inertiajs/react";
import copy from "copy-to-clipboard";
import { ArrowRight, Info, KeyRound, TriangleAlert } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { Alert, AlertDescription } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { useConfirmPhoneVerification } from "app/frontend/hooks/authentication/phone/useConfirmPhoneVerification";
import { useSendPhoneVerification } from "app/frontend/hooks/authentication/phone/useSendPhoneVerification";
import { useWebAuthnAuthentication } from "app/frontend/hooks/authentication/useWebAuthnAuthentication";
import { useWebAuthnRegistration } from "app/frontend/hooks/authentication/useWebAuthnRegistration";
import { useSecondsUntil } from "app/frontend/hooks/useSecondsUntil";
import { ROUTES } from "app/frontend/sway_constants";
import { notify } from "app/frontend/sway_utils";
import { PHONE_INPUT_TRANSFORMER, removeNonDigits } from "app/frontend/sway_utils/phone";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { trackFunnelStep } from "app/frontend/sway_utils/funnelTracker";
import { isInAppBrowser } from "app/frontend/sway_utils/inAppBrowser";
import { formatCountdown, RESEND_CODE_COOLDOWN_SECONDS } from "app/frontend/sway_utils/resendCooldown";
import { isPasskeySupported } from "app/frontend/sway_utils/webauthn";

interface IProps {
    subtitle?: string;
    title?: string;
}

interface SigninValues {
    phone: string;
    code: string;
}

const INITIAL_VALUES: SigninValues = {
    phone: "",
    code: "",
};

interface ResendWait {
    until: Date;
    seconds: number;
}

const resendCooldownFromNow = (): Date => new Date(Date.now() + RESEND_CODE_COOLDOWN_SECONDS * 1000);

const PasskeyPanel: React.FC<IProps> = ({
    title = PARITY_COPY.auth.passkeyPanel.title,
    subtitle = PARITY_COPY.auth.passkeyPanel.subtitle,
}) => {
    const codeRef = useRef<HTMLDivElement>(null);
    const phoneRef = useRef<HTMLInputElement>(null);

    const [phone, setPhone] = useState(INITIAL_VALUES.phone);
    const [code, setCode] = useState(INITIAL_VALUES.code);
    const [isConfirmingPhone, setConfirmingPhone] = useState(false);
    const [throttledUntil, setThrottledUntil] = useState<Date | null>(null);
    const [resendWait, setResendWait] = useState<ResendWait | null>(null);
    const errors = (usePage().props.errors ?? {}) as Record<string, string | undefined>;
    const inAppBrowser = isInAppBrowser();

    // @lat: [[identity-and-access#The rate limit store swaps in after boot]]
    const markThrottled = useCallback((until: Date | null) => {
        setThrottledUntil(until !== null && until.getTime() > Date.now() ? until : null);
    }, []);

    const isThrottled = useSecondsUntil(throttledUntil) > 0;

    // @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown clock on Send a new code]]
    const startResendCooldown = useCallback((until: Date | null) => {
        const seconds = until === null ? 0 : Math.ceil((until.getTime() - Date.now()) / 1000);
        setResendWait(until !== null && seconds > 0 ? { until, seconds } : null);
    }, []);

    const resendSecondsLeft = useSecondsUntil(resendWait?.until ?? null);
    const isResendCoolingDown = resendWait !== null && resendSecondsLeft > 0;

    useEffect(() => {
        if (isConfirmingPhone && codeRef.current) {
            codeRef.current.scrollIntoView({ behavior: "smooth", block: "center" });
            codeRef.current.querySelector("input")?.focus({ preventScroll: true });
        }
    }, [isConfirmingPhone]);

    const { send: sendPhoneVerification, isLoading: isLoadingSend } = useSendPhoneVerification(markThrottled);
    // @lat: [[passkey-panel-test-design#Why a refused new-code request must not latch the throttle]]
    const { send: resendPhoneVerification, isLoading: isLoadingResend } = useSendPhoneVerification(startResendCooldown);
    const {
        confirm: confirmPhoneVerification,
        isLoading: isLoadingConfirm,
        passkeyDismissed,
        clearPasskeyDismissed,
    } = useConfirmPhoneVerification(markThrottled);
    const {
        startAuthentication,
        verifyAuthentication,
        startDiscoverableAuthentication,
        verifyDiscoverableAuthentication,
        discoverableFailure,
        isLoading: isLoadingAuthentication,
    } = useWebAuthnAuthentication(markThrottled);
    const {
        startRegistration,
        verifyRegistration,
        isLoading: isLoadingRegistration,
        passkeyDismissed: resumeDismissed,
        clearPasskeyDismissed: clearResumeDismissed,
    } = useWebAuthnRegistration(markThrottled);

    // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
    useEffect(() => {
        if (!discoverableFailure) return;
        phoneRef.current?.focus({ preventScroll: true });
    }, [discoverableFailure]);

    const phoneDescribedBy = useMemo(
        () =>
            [
                discoverableFailure && !isConfirmingPhone ? "v2-passkey-fallback" : null,
                "v2-phone-hint",
                errors.phone ? "v2-phone-error" : null,
            ]
                .filter(Boolean)
                .join(" "),
        [discoverableFailure, errors.phone, isConfirmingPhone],
    );

    const isLoading = useMemo(
        () =>
            [isLoadingSend, isLoadingResend, isLoadingConfirm, isLoadingAuthentication, isLoadingRegistration].some(
                Boolean,
            ),
        [isLoadingAuthentication, isLoadingConfirm, isLoadingRegistration, isLoadingResend, isLoadingSend],
    );

    const handleSubmit = useCallback(
        async (event: React.SubmitEvent<HTMLFormElement>) => {
            event.preventDefault();

            if (removeNonDigits(phone).length !== 10) {
                notify({ level: "warning", title: PARITY_COPY.auth.passkeyPanel.validationPhone });
                return;
            }

            if (isConfirmingPhone) {
                const formCode = (new FormData(event.currentTarget).get("code") as string | null) ?? "";
                const codeToVerify = (code || formCode).trim();

                if (!codeToVerify) {
                    notify({ level: "warning", title: "Please enter your confirmation code." });
                    return;
                }

                trackFunnelStep("sms_code_entered");
                await confirmPhoneVerification(phone, codeToVerify);
                return;
            }

            // @lat: [[passkey-panel-test-design#Why the phone step checks passkey support before any request]]
            if (!isPasskeySupported()) {
                notify({ level: "error", title: PARITY_COPY.auth.passkeyPanel.passkeyUnsupported });
                return;
            }

            trackFunnelStep("phone_entered");

            try {
                const publicKey = await startAuthentication(phone);

                // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#A phone confirmed in this session resumes enrollment]]
                if (publicKey === "enroll") {
                    const credential = await startRegistration(phone);
                    if (credential) {
                        await verifyRegistration(phone, credential);
                    }
                    return;
                }

                if (typeof publicKey === "boolean") {
                    if (publicKey) {
                        startResendCooldown(resendCooldownFromNow());
                    } else {
                        notify({ level: "error", title: PARITY_COPY.auth.passkeyPanel.requestCodeError });
                    }
                    setConfirmingPhone(publicKey);
                    return;
                }

                if (!publicKey) {
                    return;
                }

                await verifyAuthentication(phone, publicKey);
            } catch (error: unknown) {
                const status =
                    error && typeof error === "object" && "response" in error
                        ? (error as { response?: { status?: number } }).response?.status
                        : undefined;

                // @lat: [[passkey-panel-test-design#Why the 422 SMS-fallback case must stay silent]]
                if (status === 422) {
                    sendPhoneVerification(phone)
                        .then((success) => {
                            setConfirmingPhone(!!success);
                            if (success) {
                                startResendCooldown(resendCooldownFromNow());
                                trackFunnelStep("sms_prompt_displayed");
                            }
                        })
                        .catch(console.error);
                    return;
                }

                // @lat: [[passkey-panel-test-design#Why an unhandled sign-in error can't fail silently]]
                notify({ level: "error", title: PARITY_COPY.auth.passkeyPanel.signInError });
            }
        },
        [
            code,
            confirmPhoneVerification,
            isConfirmingPhone,
            phone,
            sendPhoneVerification,
            startAuthentication,
            startRegistration,
            startResendCooldown,
            verifyAuthentication,
            verifyRegistration,
        ],
    );

    // @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
    const handleDiscoverableSignIn = useCallback(async () => {
        try {
            const assertion = await startDiscoverableAuthentication();
            if (assertion) {
                await verifyDiscoverableAuthentication(assertion);
            }
        } catch {
            notify({ level: "error", title: PARITY_COPY.auth.passkeyPanel.signInError });
        }
    }, [startDiscoverableAuthentication, verifyDiscoverableAuthentication]);

    const handleResend = useCallback(async () => {
        const success = await resendPhoneVerification(phone);
        if (success) {
            setCode("");
            startResendCooldown(resendCooldownFromNow());
            notify({ level: "success", title: PARITY_COPY.auth.passkeyPanel.codeResent });
        } else if (success === false) {
            notify({ level: "error", title: PARITY_COPY.auth.passkeyPanel.requestCodeError });
        }
    }, [phone, resendPhoneVerification, startResendCooldown]);

    const handleCopyLink = useCallback(async () => {
        if (await copy(window.location.href)) {
            notify({ level: "info", title: PARITY_COPY.auth.passkeyPanel.inAppBrowserLinkCopied });
        }
    }, []);

    const handleCancel = useCallback(() => {
        setCode("");
        setConfirmingPhone(false);
        clearPasskeyDismissed();
        clearResumeDismissed();
    }, [clearPasskeyDismissed, clearResumeDismissed]);

    return (
        <Card className="bg-card">
            <CardHeader className="gap-2 border-b-neo border-border-soft pb-4">
                <div className="flex items-start gap-3.5">
                    <span
                        className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-neo"
                        aria-hidden="true"
                    >
                        <KeyRound className="size-5" />
                    </span>
                    <div className="min-w-0 space-y-1">
                        <CardTitle className="text-xl font-semibold leading-snug text-foreground">
                            <h2>{title}</h2>
                        </CardTitle>
                        <CardDescription className="text-sm leading-relaxed text-muted-foreground">
                            {subtitle}
                        </CardDescription>
                    </div>
                </div>
            </CardHeader>

            <CardContent>
                {/* @lat: [[passkey-only-sms-bootstrap#Why an in-app browser is turned away before the SMS]] */}
                {inAppBrowser ? (
                    <div className="space-y-4">
                        <Alert variant="warning" data-testid="in-app-browser-notice">
                            <TriangleAlert aria-hidden="true" />
                            <AlertDescription className="space-y-1 text-foreground">
                                <strong className="block font-semibold">
                                    {PARITY_COPY.auth.passkeyPanel.inAppBrowserTitle}
                                </strong>
                                <span className="block">{PARITY_COPY.auth.passkeyPanel.inAppBrowserMessage}</span>
                            </AlertDescription>
                        </Alert>
                        <Button type="button" className="w-full" onClick={handleCopyLink}>
                            {PARITY_COPY.auth.passkeyPanel.inAppBrowserCopyLink}
                        </Button>
                    </div>
                ) : (
                    <>
                        {!isConfirmingPhone && (
                            <div className="mb-5 space-y-4">
                                <Button
                                    type="button"
                                    variant="outline"
                                    className="w-full gap-2 font-semibold"
                                    onClick={handleDiscoverableSignIn}
                                    disabled={isLoading}
                                >
                                    <KeyRound className="size-4" aria-hidden="true" />
                                    {PARITY_COPY.auth.passkeyPanel.signInWithPasskey}
                                </Button>
                                {discoverableFailure && (
                                    <Alert
                                        variant="warning"
                                        id="v2-passkey-fallback"
                                        data-testid="passkey-fallback-notice"
                                    >
                                        <TriangleAlert aria-hidden="true" />
                                        <AlertDescription className="font-semibold text-foreground">
                                            {PARITY_COPY.auth.passkeyPanel.passkeyFallback}
                                        </AlertDescription>
                                    </Alert>
                                )}
                                <div className="flex items-center gap-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                                    <span className="h-px flex-1 bg-border" aria-hidden="true" />
                                    <span className="shrink-0">
                                        {PARITY_COPY.auth.passkeyPanel.orContinueWithPhone}
                                    </span>
                                    <span className="h-px flex-1 bg-border" aria-hidden="true" />
                                </div>
                            </div>
                        )}
                        <form className="space-y-4" onSubmit={handleSubmit}>
                            <div className="space-y-2">
                                <Label htmlFor="v2-phone">{PARITY_COPY.auth.passkeyPanel.phoneLabel}</Label>
                                <Input
                                    id="v2-phone"
                                    ref={phoneRef}
                                    maxLength={16}
                                    type="tel"
                                    name="phone"
                                    // @lat: [[discoverable-passkey-design#Why the phone input carries the webauthn autocomplete token]]
                                    autoComplete="tel webauthn"
                                    aria-invalid={Boolean(errors.phone)}
                                    aria-describedby={phoneDescribedBy}
                                    value={PHONE_INPUT_TRANSFORMER.input(phone)}
                                    onChange={(event) => setPhone(PHONE_INPUT_TRANSFORMER.output(event))}
                                    disabled={isConfirmingPhone || isLoading}
                                    placeholder={PARITY_COPY.auth.passkeyPanel.phonePlaceholder}
                                />
                                <p
                                    id="v2-phone-hint"
                                    className="flex items-start gap-1.5 text-xs text-muted-foreground"
                                >
                                    <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                                    <span>
                                        Your browser may ask for permission to discover passkeys on your phone or other
                                        devices.
                                    </span>
                                </p>
                                {errors.phone && (
                                    <p
                                        id="v2-phone-error"
                                        role="alert"
                                        className="text-sm font-semibold text-destructive"
                                    >
                                        {errors.phone}
                                    </p>
                                )}
                                {!isConfirmingPhone && resumeDismissed && !isLoading && (
                                    <output aria-live="polite" className="block text-sm font-semibold text-foreground">
                                        {PARITY_COPY.auth.passkeyPanel.passkeyDismissedResume}
                                    </output>
                                )}
                            </div>

                            {isConfirmingPhone && (
                                <div ref={codeRef} className="space-y-2 animate-in fade-in duration-200">
                                    <Label htmlFor="v2-code">{PARITY_COPY.auth.passkeyPanel.codeLabel}</Label>
                                    <Input
                                        id="v2-code"
                                        maxLength={6}
                                        type="text"
                                        inputMode="numeric"
                                        pattern="[0-9]*"
                                        name="code"
                                        autoComplete="one-time-code"
                                        aria-invalid={Boolean(errors.code)}
                                        aria-describedby={errors.code ? "v2-code-error" : undefined}
                                        // @lat: [[passkey-panel-test-design#Why the code-input binding check is deliberately weak]]
                                        value={code}
                                        onChange={(event) => setCode(event.target.value)}
                                        disabled={isLoading}
                                        placeholder={PARITY_COPY.auth.passkeyPanel.codePlaceholder}
                                    />
                                    {errors.code && (
                                        <p
                                            id="v2-code-error"
                                            role="alert"
                                            className="text-sm font-semibold text-destructive"
                                        >
                                            {errors.code}
                                        </p>
                                    )}
                                    {passkeyDismissed && !isLoading && (
                                        <output className="block text-sm font-semibold text-foreground">
                                            {PARITY_COPY.auth.passkeyPanel.passkeyDismissed}
                                        </output>
                                    )}
                                </div>
                            )}

                            <div className="flex flex-col gap-2.5 pt-1">
                                <Button type="submit" className="w-full" disabled={isLoading || isThrottled}>
                                    {isConfirmingPhone
                                        ? PARITY_COPY.auth.passkeyPanel.confirmCode
                                        : PARITY_COPY.auth.passkeyPanel.continuePhone}
                                </Button>

                                {isConfirmingPhone ? (
                                    <>
                                        <div className="flex flex-col gap-1.5">
                                            <Button
                                                type="button"
                                                variant="outline"
                                                className="w-full disabled:opacity-75"
                                                onClick={handleResend}
                                                disabled={isLoading || isResendCoolingDown}
                                                aria-label={PARITY_COPY.auth.passkeyPanel.resendCode}
                                                aria-describedby="v2-resend-wait"
                                            >
                                                {PARITY_COPY.auth.passkeyPanel.resendCode}
                                            </Button>
                                            <output
                                                id="v2-resend-wait"
                                                aria-live="polite"
                                                className="block text-center text-sm font-semibold tabular-nums text-foreground"
                                            >
                                                {isResendCoolingDown && (
                                                    <>
                                                        <span aria-hidden="true" data-testid="resend-countdown">
                                                            {PARITY_COPY.auth.passkeyPanel.resendCodeIn(
                                                                formatCountdown(resendSecondsLeft),
                                                            )}
                                                        </span>
                                                        <span className="sr-only">
                                                            {PARITY_COPY.auth.passkeyPanel.resendCodeWait(
                                                                resendWait.seconds,
                                                            )}
                                                        </span>
                                                    </>
                                                )}
                                            </output>
                                        </div>
                                        <Button
                                            type="button"
                                            variant="outline"
                                            className="w-full"
                                            onClick={handleCancel}
                                            disabled={isLoading}
                                        >
                                            {PARITY_COPY.auth.passkeyPanel.cancelCta}
                                        </Button>
                                    </>
                                ) : (
                                    <Button variant="outline" className="w-full" asChild>
                                        <InertiaLink href={ROUTES.billOfTheMonth}>
                                            {PARITY_COPY.auth.passkeyPanel.previewSway}
                                            <ArrowRight className="size-4" aria-hidden="true" />
                                        </InertiaLink>
                                    </Button>
                                )}
                            </div>

                            {isLoading && (
                                <output
                                    aria-live="polite"
                                    className="flex items-center justify-center gap-3 rounded-xl border-neo border-border bg-card px-4 py-3 text-sm font-semibold text-muted-foreground shadow-neo"
                                >
                                    <img src="/images/loading.svg" alt="" className="size-5" aria-hidden="true" />
                                    <span>{PARITY_COPY.auth.passkeyPanel.workingOn}</span>
                                </output>
                            )}
                        </form>
                    </>
                )}
            </CardContent>
        </Card>
    );
};

export default PasskeyPanel;
