import { ROUTES, Support } from "app/frontend/sway_constants";
import { getId, getSelectValue, handleError, isCongressLocale, logDev, notify } from "app/frontend/sway_utils";
import { Formik } from "formik";
import { useCallback, useRef } from "react";
import { sway } from "sway";
import * as yup from "yup";

import { router, usePage } from "@inertiajs/react";
import { ISubmitValues } from "app/frontend/components/admin/types";
import { useAxiosPost } from "app/frontend/hooks/useAxios";

import BillCreatorFormikForm from "app/frontend/components/bill/creator/BillCreatorFormikForm";
import { useNewBillInitialValues } from "app/frontend/components/bill/creator/hooks/useNewBillInitialValues";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useLocale } from "app/frontend/hooks/useLocales";

const VALIDATION_SCHEMA = yup.object().shape({
    externalId: yup.string().required(),
    externalVersion: yup.string(),
    title: yup.string().required(),
    link: yup.string().required().url(),
    legislator: yup
        .object()
        .shape({
            label: yup.string(),
            value: yup.number(),
        })
        .required(),

    audioBucketPath: yup.string().nullable().notRequired(),
    houseRollCallVoteNumber: yup.number().nullable().notRequired(),
    senateRollCallVoteNumber: yup.number().nullable().notRequired(),
});

interface IProps {
    setCreatorDirty: React.Dispatch<React.SetStateAction<boolean>>;
}

const BillCreator: React.FC<IProps> = ({ setCreatorDirty }) => {
    const summaryRef = useRef<string>("");
    const [locale] = useLocale();
    const bill = usePage().props.bill as sway.IBill;
    const legislators = usePage().props.legislators as sway.ILegislator[];

    const { post: createBill } = useAxiosPost<sway.IBill>("/bills", { notifyOnValidationResultFailure: true });
    const { post: updateBill } = useAxiosPost<sway.IBill>(`/bills/${bill.id}`, {
        notifyOnValidationResultFailure: true,
        method: "put",
    });
    const { post: createLegislatorVotes } = useAxiosPost<sway.ILegislatorVote[]>("/legislator_votes", {
        notifyOnValidationResultFailure: true,
    });
    const { post: createOrganizationBillPosition } = useAxiosPost<sway.IOrganizationPosition>(
        "/organization_bill_positions",
        { notifyOnValidationResultFailure: true },
    );

    const handleCreateLegislatorVotes = useCallback(
        async (values: ISubmitValues, billId: number, setSubmitting: (s: boolean) => void) => {
            const voteLegislatorIds = values.supporters
                .concat(values.opposers)
                .concat(values.abstainers)
                .flat()
                .map(getSelectValue);

            if (voteLegislatorIds.length > legislators.length) {
                const dupes = voteLegislatorIds.filter((id: number | string, index: number) => {
                    return voteLegislatorIds.lastIndexOf(id) !== index;
                });
                notify({
                    level: "error",
                    title: `Duplicate Legislator Positions`,
                    message: `Legislators - ${dupes.join(", ")} - are duplicated in multiple positions.`,
                });
                logDev("BillOfTheWeekCreator.handleSubmit - DUPLICATE LEGISLATOR POSITION -", dupes);
                setSubmitting(false);
                return;
            }

            const votedate = values.houseVoteDateTimeUtc || values.senateVoteDateTimeUtc;
            if (!isCongressLocale(locale) && voteLegislatorIds.length !== legislators.length) {
                const missing = legislators.filter((l) => !voteLegislatorIds.includes(l.id));
                notify({
                    level: votedate ? "error" : "warning",
                    title: votedate ? "Legislators Missing" : "IGNORING Missing Legislators - No Vote Date",
                    message: `Legislators - ${missing.map((l) => l.externalId).join(", ")} - are missing support.`,
                });
                logDev("BillOfTheWeekCreator.handleSubmit - MISSING LEGISLATOR -", missing);
                // if (votedate) {
                //     setSubmitting(false);
                //     return;
                // }
            }

            const votes = [
                ...values.supporters.map((option) => ({
                    legislator_id: option.value,
                    bill_id: billId,
                    support: Support.For,
                })),
                ...values.opposers.map((option) => ({
                    legislator_id: option.value,
                    bill_id: billId,
                    support: Support.Against,
                })),
                ...values.abstainers.map((option) => ({
                    legislator_id: option.value,
                    bill_id: billId,
                    support: Support.Abstain,
                })),
            ].flat();

            if (!votes.length) return;

            return createLegislatorVotes({
                legislator_vote: {
                    votes,
                },
            }).catch(handleError);
        },
        [createLegislatorVotes, legislators, locale],
    );

    const handleCreateOrgnizationPositions = useCallback(
        async (values: ISubmitValues, billId: number) => {
            return createOrganizationBillPosition({
                organization_bill_position: {
                    positions: [
                        ...values.organizationsSupport.map((o) => ({
                            bill_id: billId,
                            organization_id: Number(o.value),
                            support: Support.For,
                            summary: o.summary,
                        })),
                        ...values.organizationsOppose.map((o) => ({
                            bill_id: billId,
                            organization_id: Number(o.value),
                            support: Support.Against,
                            summary: o.summary,
                        })),
                    ].flat(),
                },
            }).catch(handleError);
        },
        [createOrganizationBillPosition],
    );

    const handleSubmit = useCallback(
        (values: ISubmitValues, { setSubmitting }: { setSubmitting: (_isSubmitting: boolean) => void }) => {
            if (!legislators) return;

            logDev("BillOfTheWeekCreator.handleSubmit - VALUES", values);

            try {
                if (!summaryRef.current) {
                    notify({
                        level: "warning",
                        title: "Sway summary is required.",
                    });
                    console.error("summaryRef.current is falsey.");
                    setSubmitting(false);
                    return;
                }

                if (!legislators.map(getId).includes(values.legislator.value as number)) {
                    notify({
                        level: "error",
                        title: "Invalid Sponsor",
                        message: "Sponsor is not a valid legislator. Wrong locale?",
                    });
                    console.error(
                        "Invalid sponsor - values.legislator -",
                        values.legislator,
                        " - legislator ids -",
                        legislators.map(getId),
                    );
                    setSubmitting(false);
                    return;
                }

                const caller = bill.id ? updateBill : createBill;
                caller({
                    external_id: values.externalId,
                    external_version: values.externalVersion,
                    legislator_id: values.legislator.value,
                    title: values.title,
                    link: values.link,
                    chamber: values.chamber.value,
                    category: values.category.value,
                    status: values.status.value,
                    level: values.level,
                    summary: summaryRef.current,
                    introduced_date_time_utc: values.introducedDateTimeUtc,
                    house_vote_date_time_utc: values.houseVoteDateTimeUtc,
                    senate_vote_date_time_utc: values.senateVoteDateTimeUtc,
                    audio_bucket_path: values.audioBucketPath,
                    audio_by_line: values.audioByLine,
                    house_roll_call_vote_number: values.houseRollCallVoteNumber,
                    senate_roll_call_vote_number: values.senateRollCallVoteNumber,

                    // TODO:
                    // active
                })
                    .then(async (result) => {
                        if (result) {
                            await handleCreateOrgnizationPositions(values, result.id).catch(handleError);

                            await handleCreateLegislatorVotes(values, result.id, setSubmitting).catch(handleError);

                            TempBillStorage.remove();

                            router.visit(ROUTES.billOfTheWeekCreatorEdit(result.id));
                        }
                    })
                    .catch(handleError)
                    .finally(() => {
                        setSubmitting(false);
                    });
            } catch (e) {
                console.error(e);
                setSubmitting(false);
            }
        },
        [bill.id, createBill, handleCreateLegislatorVotes, handleCreateOrgnizationPositions, legislators, updateBill],
    );

    const initialValues = useNewBillInitialValues();

    return (
        <Formik
            initialValues={initialValues}
            validationSchema={VALIDATION_SCHEMA}
            onSubmit={handleSubmit}
            enableReinitialize={true}
            onReset={() => {
                logDev("RESET FORMIK");
                setCreatorDirty(false);
            }}
        >
            <BillCreatorFormikForm ref={summaryRef} setCreatorDirty={setCreatorDirty} />
        </Formik>
    );
};

export default BillCreator;
