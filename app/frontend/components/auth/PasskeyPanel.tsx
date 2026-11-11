import { Link as InertiaLink, usePage } from "@inertiajs/react";
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
import { ROUTES } from "app/frontend/sway_constants";
import { notify } from "app/frontend/sway_utils";
import { PHONE_INPUT_TRANSFORMER, removeNonDigits } from "app/frontend/sway_utils/phone";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { trackFunnelStep } from "app/frontend/sway_utils/funnelTracker";

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
    const errors = (usePage().props.errors ?? {}) as Record<string, string | undefined>;

    // @lat: [[identity-and-access#The rate limit store swaps in after boot]]
    const markThrottled = useCallback((until: Date | null) => {
        setThrottledUntil(until !== null && until.getTime() > Date.now() ? until : null);
    }, []);

    const isThrottled = throttledUntil !== null;

    useEffect(() => {
        if (!throttledUntil) return;
        const timer = window.setTimeout(
            () => setThrottledUntil(null),
            Math.max(0, throttledUntil.getTime() - Date.now()),
        );
        return () => window.clearTimeout(timer);
    }, [throttledUntil]);

    useEffect(() => {
        if (isConfirmingPhone && codeRef.current) {
            codeRef.current.scrollIntoView({ behavior: "smooth", block: "center" });
            codeRef.current.querySelector("input")?.focus({ preventScroll: true });
        }
    }, [isConfirmingPhone]);

    const { send: sendPhoneVerification, isLoading: isLoadingSend } = useSendPhoneVerification(markThrottled);
    const { confirm: confirmPhoneVerification, isLoading: isLoadingConfirm } =
        useConfirmPhoneVerification(markThrottled);
    const {
        startAuthentication,
        verifyAuthentication,
        startDiscoverableAuthentication,
        verifyDiscoverableAuthentication,
        discoverableFailure,
        isLoading: isLoadingAuthentication,
    } = useWebAuthnAuthentication(markThrottled);

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
        () => [isLoadingSend, isLoadingConfirm, isLoadingAuthentication].some(Boolean),
        [isLoadingAuthentication, isLoadingConfirm, isLoadingSend],
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

            trackFunnelStep("phone_entered");

            try {
                const publicKey = await startAuthentication(phone);

                if (typeof publicKey === "boolean") {
                    if (!publicKey) {
                        notify({ level: "error", title: PARITY_COPY.auth.passkeyPanel.validationPhoneInvalid });
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
            verifyAuthentication,
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

    const handleCancel = useCallback(() => {
        setCode("");
        setConfirmingPhone(false);
    }, []);

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
                            <Alert variant="warning" id="v2-passkey-fallback" data-testid="passkey-fallback-notice">
                                <TriangleAlert aria-hidden="true" />
                                <AlertDescription className="font-semibold text-foreground">
                                    {PARITY_COPY.auth.passkeyPanel.passkeyFallback}
                                </AlertDescription>
                            </Alert>
                        )}
                        <div className="flex items-center gap-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                            <span className="h-px flex-1 bg-border" aria-hidden="true" />
                            <span className="shrink-0">{PARITY_COPY.auth.passkeyPanel.orContinueWithPhone}</span>
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
                        <p id="v2-phone-hint" className="flex items-start gap-1.5 text-xs text-muted-foreground">
                            <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                            <span>
                                Your browser may ask for permission to discover passkeys on your phone or other devices.
                            </span>
                        </p>
                        {errors.phone && (
                            <p id="v2-phone-error" role="alert" className="text-sm font-semibold text-destructive">
                                {errors.phone}
                            </p>
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
                                <p id="v2-code-error" role="alert" className="text-sm font-semibold text-destructive">
                                    {errors.code}
                                </p>
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
                            <Button
                                type="button"
                                variant="outline"
                                className="w-full"
                                onClick={handleCancel}
                                disabled={isLoading}
                            >
                                {PARITY_COPY.auth.passkeyPanel.cancelCta}
                            </Button>
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
            </CardContent>
        </Card>
    );
};

export default PasskeyPanel;
