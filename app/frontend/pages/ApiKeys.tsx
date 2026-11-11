// @lat: [[api-keys-page-spec-contract#Key display flow]]

import { router, useForm, usePage } from "@inertiajs/react";
import copy from "copy-to-clipboard";
import { Copy, Save, Trash2 } from "lucide-react";
import { useCallback, useState } from "react";
import { sway } from "sway";

import { notify } from "app/frontend/sway_utils";
import { formatDateShort } from "app/frontend/sway_utils/datetimes";

import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent } from "app/frontend/components/ui/card";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { Input } from "app/frontend/components/ui/input";
import { cn } from "app/frontend/lib/utils";

interface IProps {
    api_keys: sway.api.IApiKey[];
}

const ApiKeys: React.FC<IProps> = ({ api_keys }) => {
    const flash = usePage<sway.IPageProps>().props.flash;
    const newApiKeyToken = flash?.new_api_key_token;
    // @lat: [[api-key-page-payload#Why ApiKeys.tsx tracks dismissed tokens in state and transforms update payloads]]
    const [dismissedToken, setDismissedToken] = useState<string | null>(null);
    const showNewKeyModal = Boolean(newApiKeyToken) && newApiKeyToken !== dismissedToken;

    const createForm = useForm({});
    const handleCreate = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            createForm.post("/api_keys", { preserveScroll: true });
        },
        [createForm],
    );

    const [editingId, setEditingId] = useState<number | null>(null);
    const [newName, setNewName] = useState<string>("");
    const updateForm = useForm({ api_keys_update_params: { name: "" } });

    const handleUpdate = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            const id = e.currentTarget.id.split("-").at(-1);
            if (!id) return;

            // @lat: [[api-key-page-payload#Why ApiKeys.tsx tracks dismissed tokens in state and transforms update payloads]]
            updateForm.transform(() => ({ api_keys_update_params: { name: newName } }));
            updateForm.put(`/api_keys/${id}`, {
                preserveScroll: true,
                onSuccess: () => {
                    setEditingId(null);
                    setNewName("");
                },
            });
        },
        [newName, updateForm],
    );

    const confirm = useConfirm();
    const handleDelete = useCallback(
        async (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            const id = e.currentTarget.id.split("-").at(-1);
            if (!id) return;

            const confirmed = await confirm({
                title: "Delete this API key?",
                description: "This revokes the key immediately. Any integration using it will stop working.",
                confirmLabel: "Delete API Key",
                tone: "destructive",
            });
            if (!confirmed) return;

            router.delete(`/api_keys/${id}`, { preserveScroll: true });
        },
        [confirm],
    );

    const handleCopy = useCallback(() => {
        if (!newApiKeyToken) return;
        copy(newApiKeyToken, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () => {
                notify({ level: "info", title: "Copied API Key" });
            },
        }).catch(() => {
            notify({ level: "error", title: "Failed to copy API Key" });
        });
    }, [newApiKeyToken]);

    const dismissNewKeyModal = useCallback(() => {
        if (newApiKeyToken) setDismissedToken(newApiKeyToken);
        router.reload({ only: ["api_keys"] });
    }, [newApiKeyToken]);

    const handleOpenChange = useCallback(
        (open: boolean) => {
            if (!open) dismissNewKeyModal();
        },
        [dismissNewKeyModal],
    );

    return (
        <div className="mx-auto w-full max-w-4xl space-y-6">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">API Keys</h1>
                <p className="text-sm text-muted-foreground">
                    Programmatic access to the Sway API. One key per admin, shown once at creation.
                </p>
            </div>

            {showNewKeyModal && newApiKeyToken && (
                <Dialog open={true} onOpenChange={handleOpenChange}>
                    <DialogContent showCloseButton={false}>
                        <DialogHeader>
                            <DialogTitle>New API Key</DialogTitle>
                            <DialogDescription>
                                Store this new API Key securely — this is the only time it will be shown.
                            </DialogDescription>
                        </DialogHeader>
                        <div className="space-y-2 text-sm">
                            <p className="text-muted-foreground">
                                If you require a new API Key, simply delete this one and create a new one. You are
                                permitted at most 1 API Key.
                            </p>
                            <div className="rounded-lg border-neo border-border-strong bg-muted/40 p-3">
                                <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                                    API Key
                                </p>
                                <button
                                    type="button"
                                    onClick={handleCopy}
                                    className="mt-1 inline-flex w-full items-center gap-2 break-all text-left font-mono text-sm text-foreground underline-offset-4 hover:underline"
                                >
                                    <span className="flex-1">{newApiKeyToken}</span>
                                    <Copy className="size-4 shrink-0" aria-hidden />
                                </button>
                            </div>
                        </div>
                        <DialogFooter>
                            <Button onClick={dismissNewKeyModal}>I saved my API Key</Button>
                        </DialogFooter>
                    </DialogContent>
                </Dialog>
            )}

            {!api_keys.length && (
                <Card>
                    <CardContent className="flex flex-col items-start gap-3 pt-6">
                        <p className="text-sm text-muted-foreground">
                            No API keys yet. Create one to start making authenticated requests.
                        </p>
                        <Button onClick={handleCreate} disabled={createForm.processing}>
                            Create API Key
                        </Button>
                    </CardContent>
                </Card>
            )}

            {api_keys.length > 0 && (
                <div className="overflow-x-auto rounded-xl border-neo border-border-strong bg-card shadow-neo">
                    <table className="w-full border-collapse text-sm tabular-nums lining-nums">
                        <thead className="bg-muted/40 text-left text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                            <tr>
                                <th scope="col" className="px-4 py-3">
                                    Name
                                </th>
                                <th scope="col" className="px-4 py-3">
                                    Created
                                </th>
                                <th scope="col" className="px-4 py-3">
                                    Last used
                                </th>
                                <th scope="col" className="px-4 py-3 text-right">
                                    <span className="sr-only">Actions</span>
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            {api_keys.map((apiKey, idx) => {
                                const isEditing = editingId === apiKey.id || !apiKey.name;
                                return (
                                    <tr
                                        key={apiKey.id}
                                        className={cn("border-t border-border-strong", idx % 2 === 1 && "bg-muted/10")}
                                    >
                                        <td className="px-4 py-3 align-middle">
                                            {apiKey.name && !isEditing ? (
                                                <span className="font-semibold text-foreground">{apiKey.name}</span>
                                            ) : (
                                                <Input
                                                    aria-label="API key name"
                                                    onChange={(e) => setNewName(e.currentTarget.value)}
                                                    onFocus={() => setEditingId(apiKey.id)}
                                                    value={newName}
                                                />
                                            )}
                                        </td>
                                        <td className="px-4 py-3 align-middle text-muted-foreground">
                                            {formatDateShort(apiKey.created_at)}
                                        </td>
                                        <td className="px-4 py-3 align-middle text-muted-foreground">
                                            {formatDateShort(apiKey.last_used_on_utc)}
                                        </td>
                                        <td className="px-4 py-3 align-middle">
                                            <div className="flex items-center justify-end gap-2">
                                                <Button
                                                    variant="default"
                                                    size="icon-sm"
                                                    onClick={handleUpdate}
                                                    id={`update-${apiKey.id.toString()}`}
                                                    disabled={!newName || updateForm.processing}
                                                    aria-label="Update API key name"
                                                    title="Update API Key Name"
                                                >
                                                    <Save aria-hidden />
                                                </Button>
                                                <Button
                                                    variant="destructive"
                                                    size="icon-sm"
                                                    onClick={handleDelete}
                                                    id={`delete-${apiKey.id.toString()}`}
                                                    aria-label="Delete API key"
                                                    title="Delete API Key"
                                                >
                                                    <Trash2 aria-hidden />
                                                </Button>
                                            </div>
                                        </td>
                                    </tr>
                                );
                            })}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
};

export default ApiKeys;
