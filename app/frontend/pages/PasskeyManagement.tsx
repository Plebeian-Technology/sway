// @lat: [[passkey-management-page-overview#Mobile: PasskeyManagementScreen]]
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { useAddPasskey } from "app/frontend/hooks/authentication/useAddPasskey";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { formatDateShort } from "app/frontend/sway_utils/datetimes";
import { router } from "@inertiajs/react";
import { KeyRound } from "lucide-react";
import { useCallback, useState } from "react";

interface PasskeyRow {
    id: number;
    label: string | null;
    created_at: string;
    last_used_at: string | null;
    device: string | null;
}

interface IProps {
    passkeys: PasskeyRow[];
}

const PasskeyManagement: React.FC<IProps> = ({ passkeys }) => {
    const { step, begin, submit, cancel } = useAddPasskey();
    const [code, setCode] = useState("");
    const [deviceName, setDeviceName] = useState("");
    const isWorking = step === "working";

    const handleSubmit = useCallback(
        (event: React.SubmitEvent<HTMLFormElement>) => {
            event.preventDefault();
            submit(code, deviceName.trim()).catch(() => {});
        },
        [submit, code, deviceName],
    );

    const handleCancel = useCallback(() => {
        setCode("");
        setDeviceName("");
        cancel();
    }, [cancel]);

    return (
        <div className="mx-auto w-full max-w-2xl space-y-6 px-4 py-6">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight text-foreground">{PARITY_COPY.passkey.title}</h1>
                <p className="text-sm text-muted-foreground">{PARITY_COPY.passkey.lead}</p>
            </div>

            <div
                className="rounded-xl border-neo border-border-strong bg-card shadow-neo px-4 py-4"
                data-testid="add-passkey"
            >
                {step === "idle" ? (
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                        <p className="text-sm text-muted-foreground">{PARITY_COPY.passkey.addLead}</p>
                        <Button
                            type="button"
                            className="shrink-0 gap-2 font-bold"
                            onClick={begin}
                            disabled={isWorking}
                            data-testid="add-passkey-start"
                        >
                            <KeyRound className="size-4" />
                            {PARITY_COPY.passkey.addCta}
                        </Button>
                    </div>
                ) : (
                    <form className="space-y-4" onSubmit={handleSubmit}>
                        <p className="text-sm text-muted-foreground">{PARITY_COPY.passkey.codeSentHint}</p>
                        <div className="grid gap-4 sm:grid-cols-2">
                            <div className="space-y-2">
                                <Label htmlFor="add-passkey-name">{PARITY_COPY.passkey.deviceNameLabel}</Label>
                                <Input
                                    id="add-passkey-name"
                                    value={deviceName}
                                    onChange={(e) => setDeviceName(e.target.value)}
                                    placeholder={PARITY_COPY.passkey.deviceNamePlaceholder}
                                    disabled={isWorking}
                                    data-testid="add-passkey-name"
                                />
                            </div>
                            <div className="space-y-2">
                                <Label htmlFor="add-passkey-code">{PARITY_COPY.passkey.codeLabel}</Label>
                                <Input
                                    id="add-passkey-code"
                                    inputMode="numeric"
                                    maxLength={6}
                                    value={code}
                                    onChange={(e) => setCode(e.target.value)}
                                    placeholder={PARITY_COPY.passkey.codePlaceholder}
                                    disabled={isWorking}
                                    data-testid="add-passkey-code"
                                />
                            </div>
                        </div>
                        <div className="flex gap-3">
                            <Button
                                type="submit"
                                className="gap-2 font-bold"
                                disabled={isWorking}
                                data-testid="add-passkey-confirm"
                            >
                                {isWorking ? PARITY_COPY.passkey.addingLabel : PARITY_COPY.passkey.addConfirmCta}
                            </Button>
                            <Button type="button" variant="outline" onClick={handleCancel} disabled={isWorking}>
                                {PARITY_COPY.passkey.cancelCta}
                            </Button>
                        </div>
                    </form>
                )}
            </div>

            {passkeys.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8" data-testid="passkey-empty">
                    {PARITY_COPY.passkey.empty}
                </p>
            ) : (
                <ul className="space-y-3" data-testid="passkey-list">
                    {passkeys.map((p) => (
                        <li
                            key={p.id}
                            data-testid={`passkey-row-${p.id}`}
                            className="rounded-xl border-neo border-border-strong bg-surface-2 shadow-neo px-4 py-3"
                        >
                            <div className="text-sm font-semibold text-foreground">{p.label ?? "Passkey"}</div>
                            <div className="text-xs text-muted-foreground">
                                {`${PARITY_COPY.passkey.devicePrefix}: ${p.device ?? PARITY_COPY.passkey.deviceUnknown}`}
                            </div>
                            <div className="text-xs text-muted-foreground tabular-nums">
                                {`${PARITY_COPY.passkey.createdOnPrefix} ${formatDateShort(p.created_at)}`}
                            </div>
                            <div className="text-xs text-muted-foreground tabular-nums">
                                {p.last_used_at
                                    ? `${PARITY_COPY.passkey.lastUsedPrefix} ${formatDateShort(p.last_used_at)}`
                                    : PARITY_COPY.passkey.neverUsed}
                            </div>
                            <div className="flex justify-end pt-2">
                                {passkeys.length > 1 && (
                                    <Button
                                        variant="destructive"
                                        size="sm"
                                        onClick={() => {
                                            if (confirm(`Are you sure you want to remove the passkey "${p.label ?? "Passkey"}"?`)) {
                                                router.delete(`/users/passkeys/${p.id}`);
                                            }
                                        }}
                                    >
                                        Remove
                                    </Button>
                                )}
                                {passkeys.length === 1 && (
                                    <p className="text-xs text-muted-foreground">
                                        {PARITY_COPY.passkey.lastPasskeyCannotBeRemoved}
                                    </p>
                                )}
                            </div>
                        </li>
                    ))}
                </ul>
            )}
        </div>
    );
};

export default PasskeyManagement;
