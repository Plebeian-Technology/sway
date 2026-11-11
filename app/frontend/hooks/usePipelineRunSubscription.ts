import { router } from "@inertiajs/react";
import consumer from "app/frontend/channels/consumer";
import { useEffect, useRef, useState } from "react";
import { logDev } from "app/frontend/sway_utils";

// @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
export interface PipelineRunSubscriptionState {
    connected: boolean;
    downgraded: boolean;
    lastDisconnectedAt: Date | null;
}

// @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
export type PipelineRunPayloadScope = "run" | "stage" | "bill";

export interface PipelineRunPayload {
    scope?: PipelineRunPayloadScope;
    // @lat: [[pipeline-run-subscription-scope-routing#Payload fields other than scope]]
    [key: string]: unknown;
}

const DOWNGRADE_GRACE_MS = 2000;

// @lat: [[pipeline-run-subscription-reload-scoping#Why bill-scoped updates narrow the reload]]
export const BILL_SCOPE_PROPS = new Set([
    "bill",
    "pipeline_run_bills",
    "bill_artifact_mirrors",
    "legislation_pipeline_run",
]);

// @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
export const narrowToBillScope = (onlyProps: readonly string[]): string[] => {
    return onlyProps.filter((p) => BILL_SCOPE_PROPS.has(p));
};

// @lat: [[pipeline-run-subscription-reload-scoping#Why bill-scoped updates narrow the reload]]
export const usePipelineRunSubscription = (
    runId: string | null,
    onlyProps: readonly string[],
): PipelineRunSubscriptionState => {
    const [state, setState] = useState<PipelineRunSubscriptionState>({
        connected: false,
        downgraded: false,
        lastDisconnectedAt: null,
    });

    // @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
    const onlyPropsRef = useRef<readonly string[]>(onlyProps);
    useEffect(() => {
        onlyPropsRef.current = onlyProps;
    }, [onlyProps]);

    const bannerTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
    // @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
    const wasDisconnected = useRef<boolean>(false);
    // @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
    const stateRef = useRef<PipelineRunSubscriptionState>(state);
    useEffect(() => {
        stateRef.current = state;
    }, [state]);

    useEffect(() => {
        if (!runId) {
            return;
        }
        const subscription = consumer.subscriptions.create(
            { channel: "PipelineRunChannel", run_id: runId },
            {
                connected() {
                    if (bannerTimer.current) {
                        clearTimeout(bannerTimer.current);
                        bannerTimer.current = null;
                    }
                    // @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
                    const wasMeaningfulDisconnect = wasDisconnected.current && stateRef.current.downgraded;
                    wasDisconnected.current = false;
                    setState({
                        connected: true,
                        downgraded: false,
                        lastDisconnectedAt: null,
                    });
                    logDev("usePipelineRunSubscription connected for run:", runId);
                    if (wasMeaningfulDisconnect) {
                        // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
                        router.reload({ only: [...onlyPropsRef.current] });
                    }
                },
                received(payload: PipelineRunPayload) {
                    // @lat: [[pipeline-run-subscription-reload-scoping#Why bill-scoped updates narrow the reload]]
                    // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
                    const scope = payload?.scope;
                    const fullOnly = [...onlyPropsRef.current];
                    // @lat: [[pipeline-run-subscription-reload-scoping#Why bill-scoped updates narrow the reload]]
                    // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
                    const billOnly = narrowToBillScope(fullOnly);
                    switch (scope) {
                        case "bill": {
                            // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
                            const propsToReload = billOnly.length > 0 ? billOnly : fullOnly;
                            logDev("usePipelineRunSubscription received bill-scoped delta", {
                                only: propsToReload,
                            });
                            router.reload({ only: propsToReload });
                            break;
                        }
                        case "run":
                        case "stage":
                            logDev("usePipelineRunSubscription received scoped delta", {
                                scope,
                                only: fullOnly,
                            });
                            router.reload({ only: fullOnly });
                            break;
                        default:
                            // @lat: [[pipeline-run-subscription-scope-routing#Prop reload routing]]
                            logDev(
                                "usePipelineRunSubscription received legacy (no-scope) delta, reloading props",
                                fullOnly,
                            );
                            router.reload({ only: fullOnly });
                    }
                },
                disconnected() {
                    wasDisconnected.current = true;
                    setState((prev) => {
                        const next = {
                            ...prev,
                            connected: false,
                            lastDisconnectedAt: new Date(),
                        };
                        stateRef.current = next;
                        return next;
                    });
                    // @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
                    bannerTimer.current = setTimeout(() => {
                        setState((prev) => {
                            const next = { ...prev, downgraded: true };
                            // @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
                            stateRef.current = next;
                            return next;
                        });
                    }, DOWNGRADE_GRACE_MS);
                },
            },
        );
        return () => {
            subscription.unsubscribe();
            if (bannerTimer.current) {
                clearTimeout(bannerTimer.current);
                bannerTimer.current = null;
            }
        };
        // @lat: [[pipeline-run-subscription-reload-scoping#Implementation: refs and timers]]
    }, [runId]);

    return state;
};
