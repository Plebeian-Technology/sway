// @lat: [[confirm-dialog-usage#useConfirm/ConfirmProvider]]

import { Dialog as DialogPrimitive } from "radix-ui";
import { createContext, useCallback, useContext, useRef, useState, type PropsWithChildren } from "react";

import { Button } from "@/components/ui/button";
import { Dialog, DialogDescription, DialogOverlay, DialogPortal, DialogTitle } from "@/components/ui/dialog";

export interface ConfirmOptions {
    title: string;
    description?: string;
    confirmLabel?: string;
    cancelLabel?: string;
    tone?: "default" | "destructive";
}

type ConfirmFn = (options: ConfirmOptions) => Promise<boolean>;

const ConfirmContext = createContext<ConfirmFn | undefined>(undefined);

// oxlint-disable-next-line react-refresh/only-export-components -- the useConfirm hook intentionally lives beside its ConfirmProvider; splitting them across files buys nothing but churn.
export function useConfirm(): ConfirmFn {
    const confirm = useContext(ConfirmContext);

    if (!confirm) {
        throw new Error("useConfirm must be used within a ConfirmProvider.");
    }

    return confirm;
}

interface ConfirmState extends ConfirmOptions {
    open: boolean;
}

// One element, responsive: a bottom sheet on phones — pinned to the bottom
// edge, rounded only at the top, sliding up — and a centered card from `sm`.
const CONTENT_CLASS = [
    "fixed inset-x-0 bottom-0 z-50 flex w-full flex-col gap-5 rounded-t-3xl border-neo",
    "border-border-strong bg-card p-5 pb-6 text-foreground shadow-neo",
    "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-1/2 sm:max-w-md sm:-translate-x-1/2 sm:-translate-y-1/2",
    "sm:rounded-xl sm:p-6",
    "data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:slide-in-from-bottom-8",
    "data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:slide-out-to-bottom-8",
].join(" ");

export function ConfirmProvider({ children }: PropsWithChildren) {
    const [state, setState] = useState<ConfirmState>({ open: false, title: "" });
    const resolverRef = useRef<((value: boolean) => void) | null>(null);

    // @lat: [[confirm-dialog-usage#useConfirm/ConfirmProvider]]
    const settle = useCallback((value: boolean) => {
        resolverRef.current?.(value);
        resolverRef.current = null;
        setState((current) => ({ ...current, open: false }));
    }, []);

    const confirm = useCallback<ConfirmFn>(
        (options) =>
            new Promise<boolean>((resolve) => {
                resolverRef.current = resolve;
                setState({ ...options, open: true });
            }),
        [],
    );

    return (
        <ConfirmContext.Provider value={confirm}>
            {children}
            <Dialog
                open={state.open}
                onOpenChange={(next) => {
                    if (!next) {
                        settle(false);
                    }
                }}
            >
                <DialogPortal>
                    <DialogOverlay />
                    <DialogPrimitive.Content className={CONTENT_CLASS}>
                        <div className="flex flex-col gap-2">
                            <DialogTitle className="text-lg font-bold">{state.title}</DialogTitle>
                            {state.description && (
                                <DialogDescription className="leading-relaxed">{state.description}</DialogDescription>
                            )}
                        </div>
                        <div className="flex flex-col-reverse gap-2.5 sm:flex-row sm:justify-end">
                            <Button
                                type="button"
                                variant="secondary"
                                className="h-11 w-full sm:h-9 sm:w-auto"
                                onClick={() => settle(false)}
                            >
                                {state.cancelLabel ?? "Cancel"}
                            </Button>
                            <Button
                                type="button"
                                variant={state.tone === "destructive" ? "destructive" : "default"}
                                className="h-11 w-full sm:h-9 sm:w-auto"
                                onClick={() => settle(true)}
                            >
                                {state.confirmLabel ?? "Confirm"}
                            </Button>
                        </div>
                    </DialogPrimitive.Content>
                </DialogPortal>
            </Dialog>
        </ConfirmContext.Provider>
    );
}
