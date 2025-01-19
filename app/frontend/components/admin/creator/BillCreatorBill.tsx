import { Button, Form } from "react-bootstrap";
import { FiSave } from "react-icons/fi";

import SwaySpinner from "app/frontend/components/SwaySpinner";

import BillCreatorFormHeader from "app/frontend/components/admin/creator/BillCreatorFormHeader";
import DateField from "app/frontend/components/admin/creator/fields/DateField";
import SelectField from "app/frontend/components/admin/creator/fields/SelectField";
import SummaryField from "app/frontend/components/admin/creator/fields/SummaryField";
import TextField from "app/frontend/components/admin/creator/fields/TextField";
import { useNewBillInitialValues } from "app/frontend/components/admin/creator/hooks/useNewBillInitialValues";
import { useTempStorage } from "app/frontend/components/admin/creator/hooks/useTempStorage";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import FormContext from "app/frontend/components/contexts/FormContext";
import { useLocale } from "app/frontend/hooks/useLocales";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";
import { notify, SWAY_STORAGE } from "app/frontend/sway_utils";
import { useCallback, useEffect, useMemo, useRef } from "react";
import { sway } from "sway";
import { useInertiaForm } from "use-inertia-form";

interface IProps {
    setCreatorDirty: React.Dispatch<React.SetStateAction<boolean>>;
}

const BillCreatorBill = ({ setCreatorDirty }: IProps) => {
    const [swayLocale] = useLocale();
    const initialValues = useNewBillInitialValues();
    const form = useInertiaForm<IApiBillCreator>(initialValues);
    const summaryRef = useRef<string>("");

    const {
        entries: { saved },
        remove,
    } = useSearchParams();
    useEffect(() => {
        if (saved) {
            notify({ level: "success", title: saved });
            window.setTimeout(() => {
                remove("saved");
            }, 2000);
        }
    }, [saved, remove]);

    useEffect(() => {
        setCreatorDirty(form.isDirty);
    }, [setCreatorDirty, form.isDirty]);

    const onSubmit: React.FormEventHandler<HTMLFormElement> = useCallback(
        (e) => {
            e.preventDefault();

            form.transform((data) => {
                return {
                    ...data,
                    summary: summaryRef.current,
                    status: (typeof form.data.status === "string"
                        ? form.data.status
                        : form.data.status?.value) as sway.TBillStatus,
                    category: (typeof form.data.category === "string"
                        ? form.data.category
                        : form.data.category?.value) as sway.TBillCategory,
                    chamber: ((typeof form.data.chamber === "string" ? form.data.chamber : form.data.chamber?.value) ||
                        "council") as sway.TBillChamber,
                    legislator_id: (typeof form.data.legislator_id === "number"
                        ? form.data.legislator_id
                        : form.data.legislator_id?.value) as number,
                    sway_locale_id: swayLocale.id,
                };
            });

            if (!form.data.status) {
                notify({
                    level: "error",
                    title: "Please select the bill status before saving.",
                });
                return;
            }
            if (!form.data.category) {
                notify({
                    level: "error",
                    title: "Please select the bill category before saving.",
                });
                return;
            }
            if (!form.data.chamber) {
                notify({
                    level: "error",
                    title: "Please select the bill chamber before saving.",
                });
                return;
            }
            if (!form.data.legislator_id) {
                notify({
                    level: "error",
                    title: "Please select the bill sponsor before saving.",
                });
                return;
            }

            const caller = initialValues.id ? form.put : form.post;
            const route = initialValues.id ? `/bills/${initialValues.id}` : "/bills";

            caller(route, { preserveScroll: true, async: true });
        },
        [form, initialValues.id, swayLocale.id],
    );

    const toStore = useMemo(
        () => ({
            ...form.data,
            summary: summaryRef.current || "",
        }),
        // eslint-disable-next-line react-hooks/exhaustive-deps
        [form.data, summaryRef.current],
    );

    const { storage, onBlur, blurredFieldName } = useTempStorage(SWAY_STORAGE.Local.BillOfTheWeek.Bill, toStore);

    return (
        <FormContext.Provider value={form}>
            <Form onSubmit={onSubmit}>
                <BillCreatorFormHeader form={form} storage={storage} blurredFieldName={blurredFieldName} />
                <div className="row">
                    <div className="my-2 col-12 col-sm-6">
                        <TextField swayField={BILL_INPUTS.external_id} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <TextField swayField={BILL_INPUTS.external_version} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <TextField swayField={BILL_INPUTS.title} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <TextField swayField={BILL_INPUTS.link} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <SelectField swayField={BILL_INPUTS.legislator_id} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <SelectField swayField={BILL_INPUTS.chamber} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <SelectField swayField={BILL_INPUTS.status} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <SelectField swayField={BILL_INPUTS.category} fieldGroupLength={1} onBlur={onBlur} />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <DateField
                            swayField={BILL_INPUTS.introduced_date_time_utc}
                            fieldGroupLength={1}
                            onBlur={onBlur}
                        />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <DateField
                            swayField={BILL_INPUTS.withdrawn_date_time_utc}
                            fieldGroupLength={1}
                            onBlur={onBlur}
                        />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <DateField
                            swayField={BILL_INPUTS.house_vote_date_time_utc}
                            fieldGroupLength={1}
                            onBlur={onBlur}
                        />
                    </div>

                    <div className="my-2 col-12 col-sm-6">
                        <DateField
                            swayField={BILL_INPUTS.senate_vote_date_time_utc}
                            fieldGroupLength={1}
                            onBlur={onBlur}
                        />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <TextField
                            swayField={BILL_INPUTS.house_roll_call_vote_number}
                            fieldGroupLength={1}
                            onBlur={onBlur}
                        />
                    </div>
                    <div className="my-2 col-12 col-sm-6">
                        <TextField
                            swayField={BILL_INPUTS.senate_roll_call_vote_number}
                            fieldGroupLength={1}
                            onBlur={onBlur}
                        />
                    </div>

                    <div className="my-2">
                        <SummaryField
                            swayField={BILL_INPUTS.summary as sway.IFormField<IApiBillCreator>}
                            onBlur={onBlur}
                            ref={summaryRef}
                        />
                    </div>
                </div>
                <div className="mx-auto text-center p-5">
                    <div className="row align-items-center">
                        <div className="col text-center">
                            <Button
                                disabled={form.processing}
                                variant="primary"
                                size="lg"
                                type="submit"
                                className="p-5 w-100"
                            >
                                <FiSave />
                                &nbsp;Save Bill
                            </Button>
                        </div>
                    </div>
                    <div className="row align-items-center mt-3">
                        <div className="col text-center">
                            <SwaySpinner isHidden={!form.processing} />
                        </div>
                    </div>
                </div>
            </Form>
        </FormContext.Provider>
    );
};

export default BillCreatorBill;
