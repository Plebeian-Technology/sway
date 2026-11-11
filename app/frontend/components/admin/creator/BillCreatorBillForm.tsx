import { useForm, usePage } from "@inertiajs/react";
import { stampSummaryProvenance } from "app/frontend/components/admin/creator/billDraftSummaryProvenance";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { useBillFormSubmit } from "app/frontend/components/admin/creator/hooks/useBillFormSubmit";
import { useNewBillInitialValues } from "app/frontend/components/admin/creator/hooks/useNewBillInitialValues";
import { useTempStorage } from "app/frontend/components/admin/creator/hooks/useTempStorage";
import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";
import { logDev, SWAY_STORAGE } from "app/frontend/sway_utils";
import { Save } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { sway } from "sway";
import { Button } from "app/frontend/components/ui/button";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";
import BillCreatorFormHeader from "app/frontend/components/admin/creator/BillCreatorFormHeader";
import DateField from "app/frontend/components/admin/creator/fields/DateField";
import SelectField from "app/frontend/components/admin/creator/fields/SelectField";
import SummaryField from "app/frontend/components/admin/creator/fields/SummaryField";
import TextField from "app/frontend/components/admin/creator/fields/TextField";

interface IProps {
    setCreatorDirty: React.Dispatch<React.SetStateAction<boolean>>;
}

interface IPageProps {
    bill?: { summary?: string | null };
    [key: string]: unknown;
}

// @lat: [[bill-creator-form-state#The details form owns its Inertia state]]
const BillCreatorBillForm: React.FC<IProps> = ({ setCreatorDirty }) => {
    const [sway_locale] = useSwayLocale();
    const initialValues = useNewBillInitialValues();
    // @lat: [[bill-creator-form-state#Published summary and draft provenance are separate]]
    const publishedSummary = usePage<IPageProps>().props.bill?.summary?.trim() ?? "";
    const form = useForm<IApiBillCreator>(initialValues);
    const { processing, reset, setData } = form;

    // @lat: [[bill-creator-form-state#Published summary and draft provenance are separate]]
    const summaryWrittenAgainstRef = useRef<string>(publishedSummary);

    // @lat: [[bill-creator-form-state#A refreshed summary replaces only untouched text]]
    const [lastPublishedSummary, setLastPublishedSummary] = useState<string>(publishedSummary);
    if (publishedSummary !== lastPublishedSummary) {
        const summaryValue = form.data.summary ?? "";
        const untouched = summaryValue === lastPublishedSummary;
        setLastPublishedSummary(publishedSummary);
        if (untouched) {
            setData("summary", publishedSummary);
        }
        if (untouched || summaryValue === publishedSummary) {
            summaryWrittenAgainstRef.current = publishedSummary;
        }
    }

    // @lat: [[bill-creator-form-state#Autosaved drafts read current form data]]
    const toStore = useCallback(
        () =>
            stampSummaryProvenance(
                {
                    ...form.data,
                    summary: form.data.summary ?? "",
                },
                summaryWrittenAgainstRef.current,
            ),
        [form.data],
    );

    const { storage, onBlur, storeField, blurredFieldName } = useTempStorage(
        SWAY_STORAGE.Local.BillCreator.Bill,
        toStore,
    );

    // @lat: [[phase-60-advisory-resolutions#Category Feature Advisory Resolutions#Modern Form Change Tracking]]
    const onSaved = useCallback(() => {
        logDev("BillCreatorBillForm.onSaved -> Set not dirty and remove temp storage.");
        setCreatorDirty(false);
        storage.remove();
    }, [storage, setCreatorDirty]);

    // @lat: [[bill-creator-form-state#The dirty flag starts clean for a new bill form]]
    useEffect(() => {
        setCreatorDirty(false);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    // @lat: [[toasts#Flash toast dedupe]]
    const { onSubmit } = useBillFormSubmit({
        form,
        initialValues,
        swayLocaleId: sway_locale?.id,
        onSaved: onSaved,
    });

    const onFormChange = useCallback(() => setCreatorDirty(true), [setCreatorDirty]);

    return (
        <SwayFormContext.Provider value={form}>
            <form onSubmit={onSubmit} onChange={onFormChange}>
                <BillCreatorFormHeader
                    storage={storage}
                    blurredFieldName={blurredFieldName}
                    processing={processing}
                    onReset={onSaved}
                    onResetForm={reset}
                />

                <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2">
                    <TextField swayField={BILL_INPUTS.external_id} onBlur={onBlur} />
                    <TextField swayField={BILL_INPUTS.external_version} onBlur={onBlur} />
                    <TextField swayField={BILL_INPUTS.title} onBlur={onBlur} />
                    <TextField swayField={BILL_INPUTS.link} onBlur={onBlur} />
                    {/* @lat: [[bill-creator-form-state#Dropdown drafts are stored after selection]] */}
                    <SelectField swayField={BILL_INPUTS.legislator_id} onStored={storeField} />
                    <SelectField swayField={BILL_INPUTS.chamber} onStored={storeField} featureNote="creator.chamber" />
                    <SelectField swayField={BILL_INPUTS.status} onStored={storeField} />
                    <DateField swayField={BILL_INPUTS.introduced_date_time_utc} onBlur={onBlur} />
                    <DateField swayField={BILL_INPUTS.withdrawn_date_time_utc} onBlur={onBlur} />
                    <DateField swayField={BILL_INPUTS.house_vote_date_time_utc} onBlur={onBlur} />
                    <DateField swayField={BILL_INPUTS.senate_vote_date_time_utc} onBlur={onBlur} />
                    <TextField swayField={BILL_INPUTS.house_roll_call_vote_number} onBlur={onBlur} />
                    <TextField swayField={BILL_INPUTS.senate_roll_call_vote_number} onBlur={onBlur} />
                </div>

                <div className="mt-8">
                    <SummaryField swayField={BILL_INPUTS.summary as sway.IFormField<IApiBillCreator>} onBlur={onBlur} />
                </div>

                <div className="mt-8 flex justify-center">
                    <Button type="submit" size="lg" disabled={processing} className="min-h-11 w-full max-w-lg">
                        <Save aria-hidden />
                        &nbsp;Save Bill
                    </Button>
                </div>
            </form>
        </SwayFormContext.Provider>
    );
};

export default BillCreatorBillForm;
