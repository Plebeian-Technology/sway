/* eslint-disable react-hooks/exhaustive-deps */

/** @format */
import { ROUTES } from "app/frontend/sway_constants";
import { logDev, REACT_SELECT_STYLES } from "app/frontend/sway_utils";
import { lazy, Suspense, useCallback, useMemo, useState } from "react";
import { Button, ButtonGroup, Form, Nav, ProgressBar, Tab } from "react-bootstrap";
import Select, { SingleValue } from "react-select";
import { ISelectOption, sway } from "sway";

import { router } from "@inertiajs/react";
import { useLocale } from "app/frontend/hooks/useLocales";

import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import SwayLogo from "app/frontend/components/SwayLogo";
import LocaleSelector from "app/frontend/components/user/LocaleSelector";

import { ETab } from "app/frontend/components/bill/creator/constants";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";

const BillCreator = lazy(() => import("app/frontend/components/bill/creator/BillCreator"));
const BillSchedule = lazy(() => import("app/frontend/components/bill/creator/BillSchedule"));

interface IProps {
    bills: sway.IBill[];
    bill: sway.IBill;
    legislators: sway.ILegislator[];
    legislatorVotes: sway.ILegislatorVote[];
    locale: sway.ISwayLocale;
    positions: sway.IOrganizationPosition[];
    user: sway.IUser;
    tabKey?: ETab;
}

const NEW_BILL_OPTION = { label: "New Bill", value: -1 };

const BillOfTheWeekCreator_: React.FC<IProps> = ({ bills, bill, user, tabKey = ETab.Creator }) => {
    const [locale] = useLocale();
    const params = useSearchParams();
    const { isAdmin } = user;

    const isLoading = useMemo(() => false, []);
    const [isCreatorDirty, setCreatorDirty] = useState<boolean>(false);

    const selectedBill = useMemo(
        () =>
            bill.id
                ? {
                      label: `${bill.externalId} - ${bill.title}`,
                      value: bill.id,
                  }
                : NEW_BILL_OPTION,
        [bill.externalId, bill.title, bill.id],
    );

    const options = useMemo(
        () =>
            (bills ?? [])
                .map((b) => ({ label: `${b.externalId} - ${b.title}`, value: b.id }))
                .concat(bill.id ? [NEW_BILL_OPTION] : []),
        [bills],
    );

    const handleChangeBill = useCallback((o: SingleValue<ISelectOption>, newParams?: Record<string, string>) => {
        if (!o) return;

        if (Number(o.value) > 0) {
            router.visit(`${ROUTES.billOfTheWeekCreatorEdit(o.value)}?${params.toQs(newParams || {})}`, {
                preserveScroll: true,
            });
        } else {
            router.visit(`${ROUTES.billOfTheWeekCreator}?${params.toQs(newParams || {})}`, {
                preserveScroll: true,
            });
        }
    }, []);

    const handleChangeTab = useCallback(
        (newTabKey: string | null) => {
            if (!newTabKey) return;

            if (isCreatorDirty && newTabKey === ETab.Schedule) {
                const isConfirmed = window.confirm(
                    "DANGER! Switching to the scheduler will remove all unsaved data from the Bill Creator. Only saved bills can be scheduled. Continue?",
                );
                if (isConfirmed) {
                    params.add("tabKey", newTabKey);
                }
            } else {
                params.add("tabKey", newTabKey);
            }
        },
        [isCreatorDirty],
    );

    if (!isAdmin || !locale) {
        logDev("BillOfTheWeekCreator - no admin OR no locale - render null");
        return null;
    }

    return (
        <div className="col">
            {isLoading && <FullScreenLoading message="Loading..." />}

            <div className="position-sticky mt-5 top-0">
                <div className="row align-items-center">
                    <div className="col">
                        <Form.Label className="my-0 bold">Sway Locale</Form.Label>
                        <LocaleSelector callahead={TempBillStorage.remove} />
                    </div>
                </div>

                <div className="row align-items-center mt-3">
                    <div className="col">
                        <Form.Label className="my-0 bold">Previous Bill of the Day</Form.Label>
                        <div className="mt-2">
                            <Select
                                name="selectedBill"
                                options={options}
                                value={selectedBill}
                                styles={REACT_SELECT_STYLES}
                                menuPortalTarget={document.body}
                                menuPosition="fixed"
                                onChange={(o) => {
                                    TempBillStorage.remove();
                                    handleChangeBill(o);
                                }}
                            />
                        </div>
                    </div>
                </div>
            </div>
            <div className="text-center my-5">
                <SwayLogo />
            </div>
            <Tab.Container
                id="creator-tabs"
                activeKey={tabKey || ETab.Creator}
                defaultActiveKey={ETab.Creator}
                onSelect={handleChangeTab}
            >
                <Nav variant="pills" className="row">
                    <div className="col">
                        <ButtonGroup className="w-100" style={{ zIndex: 0 }}>
                            <Button
                                variant={!tabKey || tabKey === ETab.Creator ? "primary" : "outline-secondary"}
                                onClick={() => handleChangeTab(ETab.Creator)}
                                disabled={!tabKey || tabKey === ETab.Creator}
                            >
                                Bill Creator
                            </Button>
                            <Button
                                variant={tabKey === ETab.Schedule ? "primary" : "outline-secondary"}
                                onClick={() => handleChangeTab(ETab.Schedule)}
                                disabled={tabKey === ETab.Schedule}
                            >
                                Scheduler
                            </Button>
                        </ButtonGroup>
                    </div>
                </Nav>
                <Tab.Content className="mt-3">
                    <Tab.Pane title="Bill Creator" eventKey={ETab.Creator}>
                        <Suspense fallback={<ProgressBar animated striped now={100} />}>
                            {(!tabKey || tabKey === ETab.Creator) && <BillCreator setCreatorDirty={setCreatorDirty} />}
                        </Suspense>
                    </Tab.Pane>
                    <Tab.Pane title="Schedule" eventKey={ETab.Schedule}>
                        <Suspense fallback={<ProgressBar animated striped now={100} />}>
                            <BillSchedule
                                params={params}
                                selectedBill={selectedBill}
                                setSelectedBill={handleChangeBill}
                            />
                        </Suspense>
                    </Tab.Pane>
                </Tab.Content>
            </Tab.Container>
        </div>
    );
};

const BillOfTheWeekCreator = BillOfTheWeekCreator_;
export default BillOfTheWeekCreator;
