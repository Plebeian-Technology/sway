import { router, usePage } from "@inertiajs/react";
import AdminSwayLocaleSelector from "app/frontend/components/admin/creator/AdminSwayLocaleSelector";
import BillCreatorAccordions from "app/frontend/components/admin/creator/BillCreatorAccordions";
import BillCreatorPicker, { NEW_BILL_VALUE } from "app/frontend/components/admin/creator/BillCreatorPicker";
import BillCreatorPipelineLlm from "app/frontend/components/admin/creator/BillCreatorPipelineLlm";
import BillCreatorPositions from "app/frontend/components/admin/creator/BillCreatorPositions";
import BillCreatorSummary from "app/frontend/components/admin/creator/BillCreatorSummary";
import BillSchedule from "app/frontend/components/admin/creator/BillSchedule";
import RunConflictBanner from "app/frontend/components/admin/creator/RunConflictBanner";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "app/frontend/components/ui/tabs";
import { ROUTES } from "app/frontend/sway_constants";
import { useCallback, useState } from "react";
import { sway } from "sway";

interface IProps {
    tabKey: ETab;
}

// @lat: [[bill-creator-shell#Why the unsaved-changes prompt guards every tab]]
const DIRTY_GUARDED_TABS: ETab[] = Object.values(ETab);

interface IBillPickerPageProps {
    bill?: sway.IBill & { id?: number };
    bills?: sway.IBillPickerOption[];
    [key: string]: unknown;
}

// @lat: [[bill-creator-shell#Why IPendingNav kind is explicit rather than inferred]]
interface IPendingNav {
    // @lat: [[bill-creator-shell#Why IPendingNav kind is explicit rather than inferred]]
    href?: string;
    kind: "bill" | "locale" | "cancel-run";
    runId?: number;
}

const BillCreatorShell: React.FC<IProps> = ({ tabKey }) => {
    const { props } = usePage<IBillPickerPageProps>();

    const currentBill = props.bill;
    const currentBillId = currentBill?.id && currentBill.id > 0 ? currentBill.id : null;

    const [isCreatorDirty, setCreatorDirty] = useState<boolean>(false);
    const [pendingTab, setPendingTab] = useState<ETab | null>(null);
    const [pendingNav, setPendingNav] = useState<IPendingNav | null>(null);
    // @lat: [[bill-interesting-score#Why locale selection stays in the shell]]
    const [pendingSwayLocaleId, setPendingSwayLocaleId] = useState<number | undefined>(undefined);

    // @lat: [[bill-creator-shell#Why the tab survives picking a different bill]]
    // @lat: [[bill-creator-shell#Why the Bill Creator carries query parameters across navigation]]
    const changeTab = useCallback(
        (nextTab: ETab) => {
            if (currentBillId) {
                router.visit(ROUTES.billCreatorTab(currentBillId, nextTab), {
                    data: {
                        bill_creator_tab: encodeURIComponent(nextTab),
                    },
                    preserveScroll: true,
                });
            } else {
                router.visit(ROUTES.billCreator, {
                    data: {
                        bill_creator_tab: encodeURIComponent(nextTab),
                    },
                    preserveScroll: true,
                });
            }
        },
        [currentBillId],
    );

    const onTabChange = useCallback(
        (next: string) => {
            const nextTab = next as ETab;
            if (isCreatorDirty && DIRTY_GUARDED_TABS.includes(nextTab)) {
                setPendingTab(nextTab);
                return;
            }
            changeTab(nextTab);
        },
        [isCreatorDirty, changeTab],
    );

    const visitBillHref = useCallback((href: string, params?: Record<string, string | number | undefined>) => {
        router.visit(href, { data: params ?? {} });
    }, []);

    const onBillChange = useCallback(
        (next: string) => {
            // @lat: [[bill-creator-shell#Why onBillChange puts both the bill id and the tab in the address]]
            const nextHref = next === NEW_BILL_VALUE ? ROUTES.billCreator : ROUTES.billCreatorTab(next, tabKey);
            if (isCreatorDirty) {
                setPendingNav({ href: nextHref, kind: "bill" });
                return;
            }
            visitBillHref(nextHref, { bill_creator_tab: encodeURIComponent(tabKey) });
        },
        [isCreatorDirty, tabKey, visitBillHref],
    );

    // @lat: [[bill-creator-shell#Why onSwayLocaleChange always returns to the empty picker]]
    const onSwayLocaleChange = useCallback(
        (swayLocaleId: number) => {
            const nextHref = ROUTES.billCreator;
            setPendingSwayLocaleId(swayLocaleId);
            if (isCreatorDirty) {
                setPendingNav({ href: nextHref, kind: "locale" });
                return;
            }
            visitBillHref(nextHref, { sway_locale_id: swayLocaleId });
        },
        [isCreatorDirty, visitBillHref],
    );

    const confirmTabChange = useCallback(() => {
        if (pendingTab) changeTab(pendingTab);
        setPendingTab(null);
    }, [changeTab, pendingTab]);

    const cancelTabChange = useCallback(() => setPendingTab(null), []);

    // @lat: [[bill-creator-shell#Why onCancelRun is the one place that sends the cancel-run DELETE]]
    const onCancelRun = useCallback(
        (runId: number) => {
            if (isCreatorDirty) {
                setPendingNav({ kind: "cancel-run", runId });
                return;
            }
            router.delete(`/bills/legislation_pipeline_runs/${runId}`, { preserveScroll: true });
        },
        [isCreatorDirty],
    );

    const confirmNav = useCallback(() => {
        if (pendingNav) {
            if (pendingNav.kind === "cancel-run" && pendingNav.runId !== undefined) {
                router.delete(`/bills/legislation_pipeline_runs/${pendingNav.runId}`, {
                    preserveScroll: true,
                });
            } else if (pendingNav.href) {
                // @lat: [[bill-creator-shell#Why confirmNav forwards pendingSwayLocaleId explicitly]]
                visitBillHref(
                    pendingNav.href,
                    pendingNav.kind === "locale" ? { sway_locale_id: pendingSwayLocaleId } : undefined,
                );
            }
        }
        setPendingNav(null);
    }, [pendingNav, pendingSwayLocaleId, visitBillHref]);

    const cancelNav = useCallback(() => {
        // @lat: [[bill-creator-shell#Why cancelNav resets pendingSwayLocaleId]]
        setPendingSwayLocaleId(undefined);
        setPendingNav(null);
    }, []);

    const isPendingDialogOpen = pendingTab !== null || pendingNav !== null;
    const closePendingDialog = useCallback(() => {
        cancelTabChange();
        cancelNav();
    }, [cancelTabChange, cancelNav]);
    const onConfirmSwitch = useCallback(() => {
        if (pendingNav) {
            confirmNav();
        } else if (pendingTab) {
            confirmTabChange();
        }
    }, [confirmNav, confirmTabChange, pendingNav, pendingTab]);

    return (
        <div className="flex flex-col gap-6">
            <RunConflictBanner onCancelRun={onCancelRun} />
            <BillCreatorPicker
                tabKey={tabKey}
                bills={props.bills ?? []}
                currentBillId={currentBillId}
                onValueChange={onBillChange}
                localeSelector={
                    <AdminSwayLocaleSelector
                        onSwayLocaleChange={onSwayLocaleChange}
                        pendingSwayLocaleId={pendingSwayLocaleId}
                    />
                }
            />

            <Tabs value={tabKey} onValueChange={onTabChange}>
                <TabsList>
                    <TabsTrigger value={ETab.Creator} className="min-h-11 md:min-h-0">
                        Bill Creator
                    </TabsTrigger>
                    <TabsTrigger value={ETab.Schedule} className="min-h-11 md:min-h-0">
                        Scheduler
                    </TabsTrigger>
                    <TabsTrigger value={ETab.PipelineLlm} className="min-h-11 md:min-h-0">
                        {"Pipeline & LLM"}
                    </TabsTrigger>
                    <TabsTrigger value={ETab.Summary} className="min-h-11 md:min-h-0">
                        Summary
                    </TabsTrigger>
                    <TabsTrigger value={ETab.Positions} className="min-h-11 md:min-h-0">
                        Positions
                    </TabsTrigger>
                </TabsList>

                <TabsContent value={ETab.Creator}>
                    <BillCreatorAccordions setCreatorDirty={setCreatorDirty} />
                </TabsContent>
                <TabsContent value={ETab.Schedule}>
                    <BillSchedule />
                </TabsContent>
                <TabsContent value={ETab.PipelineLlm}>
                    <BillCreatorPipelineLlm onCancelRun={onCancelRun} />
                </TabsContent>
                <TabsContent value={ETab.Summary}>
                    <BillCreatorSummary />
                </TabsContent>
                <TabsContent value={ETab.Positions}>
                    <BillCreatorPositions setCreatorDirty={setCreatorDirty} />
                </TabsContent>
            </Tabs>

            <Dialog open={isPendingDialogOpen} onOpenChange={(open) => !open && closePendingDialog()}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Unsaved changes</DialogTitle>
                        {/* @lat: [[bill-creator-shell#Why the unsaved-changes dialog has one sentence per action kind]] */}
                        <DialogDescription>
                            {pendingNav?.kind === "locale"
                                ? "Changing jurisdiction takes you back to the empty bill picker. Your fields are " +
                                  "saved in this browser, but only for one bill at a time — the next bill you open " +
                                  "there, in either jurisdiction, replaces this draft. Anything you are typing " +
                                  "right now is saved only when you leave the field. Continue?"
                                : pendingNav?.kind === "bill"
                                  ? "Your fields are saved in this browser, but only for one bill at a time. Working " +
                                    "on another bill replaces this draft. Anything you are typing right now is saved " +
                                    "only when you leave the field. Continue?"
                                  : pendingNav?.kind === "cancel-run"
                                    ? "Cancelling the run takes you to wherever its bill lives, which may not be the " +
                                      "bill on screen now. Your fields are saved in this browser, but only for one " +
                                      "bill at a time. Anything you are typing right now is saved only when you " +
                                      "leave the field. Continue?"
                                    : "Your fields are saved in this browser and come back when you return. Two " +
                                      "things do not: what you are typing right now, and your unsaved summary if " +
                                      "somebody saves a different one while you are away. Continue?"}
                        </DialogDescription>
                    </DialogHeader>
                    <DialogFooter>
                        <Button variant="outline" onClick={closePendingDialog}>
                            Stay
                        </Button>
                        {/* @lat: [[bill-creator-shell#Why the confirm button is not destructive]] */}
                        <Button variant="default" onClick={onConfirmSwitch}>
                            {pendingNav?.kind === "locale"
                                ? "Change jurisdiction"
                                : pendingNav?.kind === "bill"
                                  ? "Switch bill"
                                  : pendingNav?.kind === "cancel-run"
                                    ? "Cancel run"
                                    : "Switch tab"}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </div>
    );
};

export default BillCreatorShell;
