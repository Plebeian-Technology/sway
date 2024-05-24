/* eslint-disable react-hooks/exhaustive-deps */

/** @format */
import { ESwayLevel, ROUTES, Support } from "app/frontend/sway_constants";
import { getId, getSelectValue, isCongressLocale, logDev, toSelectOption } from "app/frontend/sway_utils";
import { Formik, Form as FormikForm } from "formik";
import { useCallback, useMemo, useRef } from "react";
import { Button, Form } from "react-bootstrap";
import "react-datepicker/dist/react-datepicker.css";
import { FiSave } from "react-icons/fi";
import Select, { SingleValue } from "react-select";
import { ISelectOption, sway } from "sway";
import * as yup from "yup";

import { router } from "@inertiajs/react";
import BillCreatorFields from "app/frontend/components/admin/creator/BillCreatorFields";
import { ISubmitValues } from "app/frontend/components/admin/types";
import SetupPage from "app/frontend/components/hoc/SetupPage";
import { useAxiosPost } from "app/frontend/hooks/useAxios";
import { useLocale } from "app/frontend/hooks/useLocales";
import SwaySpinner from "../components/SwaySpinner";

import SwayLogo from "app/frontend/components/SwayLogo";
import BillComponent from "app/frontend/components/bill/BillComponent";
import LocaleSelector from "app/frontend/components/user/LocaleSelector";
import FullScreenLoading from "../components/dialogs/FullScreenLoading";
import { handleError, notify } from "../sway_utils";

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
});

interface IProps {
    bills: sway.IBill[];
    bill: sway.IBill;
    legislators: sway.ILegislator[];
    legislatorVotes: sway.ILegislatorVote[];
    locale: sway.ISwayLocale;
    positions: sway.IOrganizationPosition[];
    user: sway.IUser;
}

const _BillOfTheWeekCreator: React.FC<IProps> = ({
    bills,
    bill,
    legislators,
    legislatorVotes,
    positions: organizationPositions,
    user,
}) => {
    const summaryRef = useRef<string>("");
    const [locale] = useLocale();
    const { isAdmin } = user;

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

    const isLoading = useMemo(() => false, []);

    const selectedBill = useMemo(
        () =>
            bill.id
                ? {
                      label: `${bill.externalId} - ${bill.title}`,
                      value: bill.id,
                  }
                : { label: "New Bill", value: -1 },
        [bill.externalId, bill.title, bill.id],
    );

    const options = useMemo(
        () =>
            (bills ?? [])
                .map((b) => ({ label: `${b.externalId} - ${b.title}`, value: b.id }))
                .concat(bill.id ? [{ label: "New Bill", value: -1 }] : []),
        [bills],
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
        [createLegislatorVotes],
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
            if (!isAdmin || !legislators) return;

            try {
                if (!summaryRef.current) {
                    notify({
                        level: "warning",
                        title: "Sway summary is required.",
                    });
                    setSubmitting(false);
                    return;
                }

                if (!legislators.map(getId).includes(values.legislator.value as number)) {
                    notify({
                        level: "error",
                        title: "Invalid Sponsor",
                        message: "Sponsor is not a valid legislator. Wrong locale?",
                    });
                    setSubmitting(false);
                    return;
                }

                logDev("BillOfTheWeekCreator.handleSubmit - VALUES", values);

                const caller = bill.id ? updateBill : createBill;
                caller({
                    external_id: values.externalId,
                    external_version: values.externalVersion,
                    legislator_id: values.legislator.value,
                    summary: summaryRef.current,
                    introduced_date_time_utc: values.introducedDateTimeUtc,
                    house_vote_date_time_utc: values.houseVoteDateTimeUtc,
                    senate_vote_date_time_utc: values.senateVoteDateTimeUtc,
                    category: values.category.value,
                    status: values.status.value,
                    audio_bucket_path: values.audioBucketPath,
                    audio_by_line: values.audioByLine

                    // TODO:
                    // active
                })
                    .then(async (result) => {
                        if (result) {
                            await handleCreateOrgnizationPositions(values, result.id).catch(handleError);

                            await handleCreateLegislatorVotes(values, result.id, setSubmitting).catch(handleError);

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
        [],
    );

    const initialBill = useMemo(
        () => ({
            id: bill.id,
            externalId: bill?.externalId?.trim() || "",
            externalVersion: bill?.externalVersion?.trim() || "",
            title: bill?.title?.trim() || "",
            link: bill?.link?.trim() || "",
            legislatorId: bill?.legislatorId || null,
            chamber: bill?.chamber || (isCongressLocale(locale) ? "house" : "council"),
            level: bill?.level?.trim() || ESwayLevel.Local,
            summary: bill?.summary?.trim() ?? "",
            category: bill?.category ? toSelectOption(bill.category.trim(), bill.category.trim()) : undefined,
            status: bill?.status?.trim() ?? "",
            active: typeof bill?.active === "boolean" ? bill.active : true,

            introducedDateTimeUtc: bill?.introducedDateTimeUtc ?? "",
            houseVoteDateTimeUtc: bill?.houseVoteDateTimeUtc ?? "",
            senateVoteDateTimeUtc: bill?.senateVoteDateTimeUtc ?? "",

            swayLocaleId: locale.id,

            audioBucketPath: bill?.audioBucketPath?.trim() || "",
            audioByLine: bill?.audioByLine?.trim() || "",
        }),
        [bill, locale],
    );

    const { supporters, opposers, abstainers } = useMemo(() => {
        const s = [] as ISelectOption[];
        const o = [] as ISelectOption[];
        const a = [] as ISelectOption[];
        for (const lv of legislatorVotes) {
            const legislator = legislators.find((l) => l.id === lv.legislatorId);
            if (!legislator) continue;

            switch (lv.support) {
                case Support.For:
                    s.push({ label: legislator.fullName, value: lv.legislatorId });
                    break;
                case Support.Against:
                    o.push({ label: legislator.fullName, value: lv.legislatorId });
                    break;
                case Support.Abstain:
                    a.push({ label: legislator.fullName, value: lv.legislatorId });
                    break;
            }
        }
        return { supporters: s, opposers: o, abstainers: a };
    }, []);

    const initialValues = useMemo(
        () =>
            ({
                ...initialBill,
                legislator: legislatorToSelectOption(legislators.find((l) => l.id === initialBill.legislatorId)),

                supporters,
                opposers,
                abstainers,

                organizationsSupport: (organizationPositions || [])
                    .filter((p) => p.support === Support.For)
                    .map((p) => ({
                        label: p.organization.name,
                        value: p.organization.id,
                        summary: p.summary,
                        iconPath: p.organization.iconPath,
                    })),
                organizationsOppose: (organizationPositions || [])
                    .filter((p) => p.support === Support.Against)
                    .map((p) => ({
                        label: p.organization.name,
                        value: p.organization.id,
                        summary: p.summary,
                        iconPath: p.organization.iconPath,
                    })),
            }) as ISubmitValues,
        [initialBill, legislators, organizationPositions, supporters, opposers, abstainers],
    );

    const handleChangeBill = useCallback((o: SingleValue<ISelectOption>) => {
        if (!o) return;
        if (Number(o.value) > 0) {
            router.visit(ROUTES.billOfTheWeekCreatorEdit(o.value));
        } else {
            router.visit(ROUTES.billOfTheWeekCreator);
        }
    }, []);

    if (!isAdmin || !locale) {
        logDev("BillOfTheWeekCreator - no admin OR no locale - render null");
        return null;
    }

    return (
        <div className="col">
            {isLoading && <FullScreenLoading message="Loading..." />}

            <div className="row align-items-center mt-5">
                <div className="col">
                    <Form.Label className="my-0 bold">Sway Locale</Form.Label>
                    <LocaleSelector />
                </div>

                <div className="col">
                    <Form.Label className="my-0 bold">Previous Bill of the Day</Form.Label>
                    <div className="mt-2">
                        <Select
                            name="selectedBill"
                            options={options}
                            value={selectedBill}
                            onChange={handleChangeBill}
                        />
                    </div>
                </div>
            </div>
            <div className="text-center my-5">
                <SwayLogo />
            </div>
            <Formik
                initialValues={initialValues}
                validationSchema={VALIDATION_SCHEMA}
                onSubmit={handleSubmit}
                enableReinitialize={true}
                onReset={() => logDev("RESET FORMIK")}
            >
                {(formik) => {
                    return (
                        <>
                            <FormikForm>
                                <BillCreatorFields ref={summaryRef} legislators={legislators} />
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
                            <BillComponent
                                bill={{
                                    ...formik.values,
                                    summary: summaryRef.current,
                                    legislatorId: formik.values.legislator?.value as number,
                                }}
                                positions={formik.values.organizationsSupport
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
                                    )}
                                sponsor={
                                    legislators.find(
                                        (l) => l.id === (formik.values.legislator?.value as number),
                                    ) as sway.ILegislator
                                }
                                legislatorVotes={formik.values.supporters
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
                                    .flat()}
                            />
                        </>
                    );
                }}
            </Formik>
        </div>
    );
};

const legislatorToSelectOption = (legislator?: sway.ILegislator | null) => {
    if (!legislator) return;

    return {
        label: legislator.fullName,
        value: legislator.id,
    };
};

// const BillOfTheWeekCreator = SetupPage(_BillOfTheWeekCreator);
const BillOfTheWeekCreator = _BillOfTheWeekCreator;
export default BillOfTheWeekCreator;
