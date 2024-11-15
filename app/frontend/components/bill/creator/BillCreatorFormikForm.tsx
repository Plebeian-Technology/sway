import { Support } from "app/frontend/sway_constants";
import { Form as FormikForm, useFormikContext } from "formik";
import { Button } from "react-bootstrap";
import { FiSave } from "react-icons/fi";
import { sway } from "sway";

import BillCreatorFields from "app/frontend/components/admin/creator/BillCreatorFields";
import SwaySpinner from "app/frontend/components/SwaySpinner";

import BillComponent from "app/frontend/components/bill/BillComponent";

import { usePage } from "@inertiajs/react";
import { ISubmitValues } from "app/frontend/components/admin/types";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { logDev } from "app/frontend/sway_utils";
import { forwardRef, useEffect, useMemo, useState } from "react";

interface IProps {
    setCreatorDirty: React.Dispatch<React.SetStateAction<boolean>>;
}

const BillCreatorFormikForm = forwardRef(({ setCreatorDirty }: IProps, _summaryRef: React.ForwardedRef<string>) => {
    const summaryRef = _summaryRef as React.MutableRefObject<string>;
    const formik = useFormikContext<ISubmitValues>();

    const bill = usePage().props.bill as sway.IBill;
    const legislators = usePage().props.legislators as sway.ILegislator[];

    useEffect(() => {
        setCreatorDirty(formik.dirty);
    }, [setCreatorDirty, formik.dirty]);

    const [countdown, setCountdown] = useState<number>(3);

    useEffect(() => {
        setCountdown(3);
        const timeout = window.setTimeout(() => {
            logDev("TIMEOUT - STORE BILL");
            TempBillStorage.set({
                ...formik.values,
                summary: summaryRef.current || "",
            });
        }, 5000);

        const interval = window.setInterval(() => {
            setCountdown((current) => current - 1);
        }, 1000);

        return () => {
            window.clearTimeout(timeout);
            window.clearInterval(interval);
        };
    }, [formik.values, summaryRef]);

    const positions = useMemo(
        () =>
            formik.values.organizationsSupport
                .map(
                    (p) =>
                        ({
                            support: Support.For,
                            summary: p.summary,
                            organization: {
                                id: p.value,
                                name: p.label,
                                iconPath: p.iconPath,
                            },
                        }) as sway.IOrganizationPosition,
                )
                .concat(
                    formik.values.organizationsOppose.map(
                        (p) =>
                            ({
                                support: Support.Against,
                                summary: p.summary,
                                organization: {
                                    id: p.value,
                                    name: p.label,
                                    iconPath: p.iconPath,
                                },
                            }) as sway.IOrganizationPosition,
                    ),
                ),
        [formik.values.organizationsSupport, formik.values.organizationsOppose],
    );

    const legislatorVotes = useMemo(
        () =>
            formik.values.supporters
                .map(
                    (s) =>
                        ({
                            legislatorId: s.value,
                            support: Support.For,
                            billId: bill.id || -1,
                        }) as sway.ILegislatorVote,
                )
                .concat(
                    formik.values.opposers.map(
                        (s) =>
                            ({
                                legislatorId: s.value,
                                support: Support.Against,
                                billId: bill.id || -1,
                            }) as sway.ILegislatorVote,
                    ),
                )
                .concat(
                    formik.values.abstainers.map(
                        (s) =>
                            ({
                                legislatorId: s.value,
                                support: Support.Abstain,
                                billId: bill.id || -1,
                            }) as sway.ILegislatorVote,
                    ),
                )
                .flat(),
        [formik.values.supporters, formik.values.opposers, formik.values.abstainers, bill.id],
    );

    const sponsor = useMemo(
        () => legislators.find((l) => l.id === (formik.values.legislator?.value as number)) as sway.ILegislator,
        [formik.values.legislator?.value, legislators],
    );

    return (
        <>
            <FormikForm>
                <div className={countdown >= 0 && countdown <= 3 ? "visible my-2" : "invisible my-2"}>
                    Store Temporary Bill in: {countdown}
                </div>
                <BillCreatorFields ref={summaryRef} />
                <div className="mx-auto text-center p-5">
                    <div className="row align-items-center">
                        <div className="col text-center">
                            <Button
                                disabled={formik.isSubmitting}
                                variant="primary"
                                size="lg"
                                type="submit"
                                className="p-5 w-50"
                            >
                                <FiSave />
                                &nbsp;Save
                            </Button>
                        </div>
                    </div>
                    <div className="row align-items-center mt-3">
                        <div className="col text-center">
                            <SwaySpinner isHidden={!formik.isSubmitting} />
                        </div>
                    </div>
                </div>
            </FormikForm>
            <hr />
            <div className="bolder h2">Bill of the Week Preview</div>
            <BillComponent bill={bill} positions={positions} sponsor={sponsor} legislatorVotes={legislatorVotes} />
        </>
    );
});

export default BillCreatorFormikForm;
