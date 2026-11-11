import { router, useForm, usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { useUser } from "app/frontend/hooks/users/useUser";
import { notify } from "app/frontend/sway_utils";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
}

interface IPageProps extends Record<string, unknown> {
    email_preview?: sway.IEmailPreview;
    user_legislator_emails?: sway.IUserLegislatorEmail[];
}

const STATUS_TONE = {
    pending: "neutral",
    sending: "info",
    sent: "success",
    failed: "danger",
} as const;

const EMAIL_VERIFICATION_ROUTE = "/users/email_verification";
const USER_LEGISLATOR_EMAILS_ROUTE = "/user_legislator_emails";

// @lat: [[email-verifications-controller-notes#Frontend: EmailLegislatorsModal.tsx]]
const EmailLegislatorsModal: React.FC<IProps> = ({ bill }) => {
    const user = useUser();
    const { props } = usePage<IPageProps>();
    const emailPreview = props.email_preview;
    const statuses = props.user_legislator_emails ?? [];

    const [open, setOpen] = useState(false);
    const [awaitingCode, setAwaitingCode] = useState(false);

    const isVerified = Boolean(user?.email) && Boolean(user?.is_email_verified);

    const emailForm = useForm<{ email: string; bill_id: number }>({ email: "", bill_id: bill.id });
    const codeForm = useForm<{ code: string; bill_id: number }>({ code: "", bill_id: bill.id });
    const sendForm = useForm<{ full_name: string; bill_id: number }>({
        full_name: user?.full_name ?? "",
        bill_id: bill.id,
    });

    const submitEmail = useCallback(
        (e: React.SubmitEvent<HTMLFormElement>) => {
            e.preventDefault();
            emailForm.post(EMAIL_VERIFICATION_ROUTE, {
                preserveScroll: true,
                onSuccess: () => setAwaitingCode(true),
                onError: () => notify({ level: "error", title: "Could not send the verification code." }),
            });
        },
        [emailForm],
    );

    const submitCode = useCallback(
        (e: React.SubmitEvent<HTMLFormElement>) => {
            e.preventDefault();
            codeForm.patch(EMAIL_VERIFICATION_ROUTE, {
                preserveScroll: true,
                onError: () => notify({ level: "error", title: "Could not verify that code." }),
            });
        },
        [codeForm],
    );

    const startOver = useCallback(() => {
        router.delete(EMAIL_VERIFICATION_ROUTE, {
            data: { bill_id: bill.id },
            preserveScroll: true,
            onFinish: () => {
                setAwaitingCode(false);
                emailForm.setData("email", "");
                codeForm.setData("code", "");
            },
        });
    }, [bill.id, emailForm, codeForm]);

    const submitSend = useCallback(
        (e: React.SubmitEvent<HTMLFormElement>) => {
            e.preventDefault();
            sendForm.post(USER_LEGISLATOR_EMAILS_ROUTE, {
                preserveScroll: true,
                onSuccess: () => setOpen(false),
                onError: () => notify({ level: "error", title: "Could not send your message." }),
            });
        },
        [sendForm],
    );

    const title = !isVerified
        ? awaitingCode
            ? "Verify Your Email"
            : "What's Your Email?"
        : "Message Your Legislators";

    return (
        <>
            <Button type="button" variant="outline" onClick={() => setOpen(true)} data-testid="btn-email-legislators">
                Email your representatives
            </Button>

            <Dialog open={open} onOpenChange={setOpen}>
                <DialogContent className="max-w-xl">
                    <DialogHeader>
                        <DialogTitle>{title}</DialogTitle>
                    </DialogHeader>

                    {statuses.length > 0 && (
                        <div className="space-y-2" data-testid="legislator-email-statuses">
                            {statuses.map((entry) => (
                                <div key={entry.id} className="flex items-center justify-between gap-3 text-sm">
                                    <span>{entry.legislator_full_name}</span>
                                    <Badge variant="stamp" tone={STATUS_TONE[entry.status] ?? "neutral"}>
                                        {entry.status}
                                    </Badge>
                                </div>
                            ))}
                        </div>
                    )}

                    {!isVerified && !awaitingCode && (
                        <form onSubmit={submitEmail} className="space-y-4" data-testid="email-entry-step">
                            <DialogDescription>
                                In order to email your representatives, Sway needs your email address. For now it cannot
                                be changed so please make sure to enter it accurately.
                            </DialogDescription>
                            <div className="space-y-2">
                                <Label htmlFor="ulem-email">Email</Label>
                                <Input
                                    id="ulem-email"
                                    type="email"
                                    name="email"
                                    autoComplete="email"
                                    required
                                    value={emailForm.data.email}
                                    onChange={(e) => emailForm.setData("email", e.target.value)}
                                />
                                {emailForm.errors.email && (
                                    <p className="text-sm text-destructive">{emailForm.errors.email}</p>
                                )}
                            </div>
                            <DialogFooter>
                                <Button type="submit" disabled={emailForm.processing || !emailForm.data.email}>
                                    {emailForm.processing ? "Sending…" : "Submit"}
                                </Button>
                            </DialogFooter>
                        </form>
                    )}

                    {!isVerified && awaitingCode && (
                        <form onSubmit={submitCode} className="space-y-4" data-testid="email-code-step">
                            <DialogDescription>
                                Please verify your email by entering the code we just sent you.
                            </DialogDescription>
                            <div className="space-y-2">
                                <Label htmlFor="ulem-code">Code</Label>
                                <Input
                                    id="ulem-code"
                                    name="code"
                                    maxLength={6}
                                    autoComplete="one-time-code"
                                    required
                                    value={codeForm.data.code}
                                    onChange={(e) => codeForm.setData("code", e.target.value)}
                                />
                                {codeForm.errors.code && (
                                    <p className="text-sm text-destructive">{codeForm.errors.code}</p>
                                )}
                            </div>
                            <DialogFooter>
                                <Button type="button" variant="outline" onClick={startOver}>
                                    Start Over
                                </Button>
                                <Button type="submit" disabled={codeForm.processing || !codeForm.data.code}>
                                    {codeForm.processing ? "Verifying…" : "Verify"}
                                </Button>
                            </DialogFooter>
                        </form>
                    )}

                    {isVerified && (
                        <form onSubmit={submitSend} className="space-y-4" data-testid="email-send-step">
                            {!user?.full_name && (
                                <div className="space-y-2">
                                    <DialogDescription>
                                        Sway needs your name to give your representatives more details about you.
                                    </DialogDescription>
                                    <Label htmlFor="ulem-full-name">Name</Label>
                                    <Input
                                        id="ulem-full-name"
                                        name="full_name"
                                        maxLength={100}
                                        autoComplete="name"
                                        required
                                        value={sendForm.data.full_name}
                                        onChange={(e) => sendForm.setData("full_name", e.target.value)}
                                    />
                                    {sendForm.errors.full_name && (
                                        <p className="text-sm text-destructive">{sendForm.errors.full_name}</p>
                                    )}
                                </div>
                            )}

                            {emailPreview && (
                                <div className="space-y-2">
                                    <DialogDescription>
                                        Below is the email each of your representatives will receive:
                                    </DialogDescription>
                                    <div
                                        className="space-y-2 rounded-xl border border-border bg-surface-2 p-4 text-sm"
                                        data-testid="email-preview"
                                    >
                                        <p>{emailPreview.intro}</p>
                                        <p>
                                            {emailPreview.body}
                                            {emailPreview.bill_link}
                                        </p>
                                        <p>{emailPreview.conclusion}</p>
                                    </div>
                                </div>
                            )}
                            {/* @lat: [[email-verifications-controller-notes#Frontend: EmailLegislatorsModal.tsx]] */}
                            {(sendForm.errors as Record<string, string | undefined>).email && (
                                <p className="text-sm text-destructive">
                                    {(sendForm.errors as Record<string, string | undefined>).email}
                                </p>
                            )}

                            <DialogFooter>
                                <Button
                                    type="submit"
                                    disabled={sendForm.processing || (!user?.full_name && !sendForm.data.full_name)}
                                >
                                    {sendForm.processing ? "Sending…" : "Send"}
                                </Button>
                            </DialogFooter>
                        </form>
                    )}
                </DialogContent>
            </Dialog>
        </>
    );
};

export default EmailLegislatorsModal;
