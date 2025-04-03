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

import BillCreatorAccordions from "app/frontend/components/admin/creator/BillCreatorAccordions";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";

const BillSchedule = lazy(() => import("app/frontend/components/bill/creator/BillSchedule"));

interface IProps {
    bills: sway.IBill[];
    bill: sway.IBill & { organizations: sway.IOrganization[] };
    legislators: sway.ILegislator[];
    legislator_votes: sway.ILegislatorVote[];
    locale: sway.ISwayLocale;
    organizations: sway.IOrganization[];
    user: sway.IUser;
    tab_key?: ETab;
}

const NEW_BILL_OPTION = { label: "New Bill", value: -1 };

const BillOfTheWeekCreator_: React.FC<IProps> = ({ bills, bill, user, tab_key = ETab.Creator }) => {
    const [locale] = useLocale();
    const params = useSearchParams();
    const { is_admin } = user;

    const isLoading = useMemo(() => false, []);
    const [isCreatorDirty, setCreatorDirty] = useState<boolean>(false);

    const selectedBill = useMemo(
        () =>
            bill.id && bill.sway_locale_id === locale.id
                ? {
                      label: `${bill.external_id} - ${bill.title}`,
                      value: bill.id,
                  }
                : NEW_BILL_OPTION,
        [bill.external_id, bill.title, bill.id, bill.sway_locale_id, locale.id],
    );

    const options = useMemo(
        () =>
            [NEW_BILL_OPTION].concat(
                (bills ?? []).map((b) => ({
                    label: `${b.external_id} - ${b.title} - Sway Release: ${b.scheduled_release_date_utc || "None"}`,
                    value: b.id,
                })),
            ),
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
                    params.add("tab_key", newTabKey);
                }
            } else {
                params.add("tab_key", newTabKey);
            }
        },
        [isCreatorDirty],
    );

    if (!is_admin || !locale) {
        logDev("BillOfTheWeekCreator - no admin OR no locale - render null");
        return null;
    }

    return (
        <div className="col">
            {isLoading && <FullScreenLoading message="Loading..." />}

            <div
                className="position-sticky bg-white px-3 pb-3 border border-secondary"
                style={{ zIndex: 100, borderRadius: 5, top: "56px" }}
            >
                <div className="row align-items-center mt-0">
                    <div className="col">
                        <LocaleSelector callahead={TempBillStorage.remove} labelClassName={"d-none d-md-block"} />
                    </div>
                </div>

                <div className="row align-items-center">
                    <div className="col">
                        <Form.Label className="my-0 bold d-none d-md-block">Previous Bill of the Day</Form.Label>
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
            <div className="text-center my-5">
                <SwayLogo />
            </div>
            <Tab.Container id="creator-tabs" activeKey={tab_key || ETab.Creator} onSelect={handleChangeTab}>
                <Nav variant="pills" className="row">
                    <div className="col">
                        <ButtonGroup className="w-100" style={{ zIndex: 0 }}>
                            <Button
                                variant={!tab_key || tab_key === ETab.Creator ? "primary" : "outline-secondary"}
                                onClick={() => handleChangeTab(ETab.Creator)}
                                disabled={!tab_key || tab_key === ETab.Creator}
                            >
                                Bill Creator
                            </Button>
                            <Button
                                variant={tab_key === ETab.Schedule ? "primary" : "outline-secondary"}
                                onClick={() => handleChangeTab(ETab.Schedule)}
                                disabled={tab_key === ETab.Schedule}
                            >
                                Scheduler
                            </Button>
                        </ButtonGroup>
                    </div>
                </Nav>
                <Tab.Content className="mt-3">
                    <Tab.Pane title="Bill Creator" eventKey={ETab.Creator}>
                        <Suspense fallback={<ProgressBar animated striped now={100} />}>
                            {(!tab_key || tab_key === ETab.Creator) && (
                                <BillCreatorAccordions setCreatorDirty={setCreatorDirty} />
                            )}
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
