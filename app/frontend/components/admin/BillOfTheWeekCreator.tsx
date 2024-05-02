/* eslint-disable react-hooks/exhaustive-deps */

/** @format */
import {
    CONGRESS_LOCALE_NAME,
    ESwayLevel,
    Support
} from "app/frontend/sway_constants";
import {
    isCongressLocale,
    isEmptyObject,
    logDev,
    titleize,
    toFormattedLocaleName,
} from "app/frontend/sway_utils";
import { Formik, Form as FormikForm, FormikProps } from "formik";
import { get, sortBy } from "lodash";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Button, Form } from "react-bootstrap";
import DatePicker from "react-datepicker";
import "react-datepicker/dist/react-datepicker.css";
import { FiSave } from "react-icons/fi";
import Select, { MultiValue, Options, SingleValue } from "react-select";
import { sway } from "sway";
import * as Yup from "yup";
import { useBill } from "../../hooks/bills/useBill";
import { EUseBillsFilters, useBills } from "../../hooks/bills/useBills";
import { useCancellable } from "../../hooks/useCancellable";
import { useLegislatorVotes } from "../../hooks/useLegislatorVotes";

import { useLocale } from "app/frontend/hooks/useLocales";
import {
    handleError,
    notify,
    REACT_SELECT_STYLES,
    toSelectOption,
} from "../../sway_utils";
import BillCreatorSummary from "../bill/BillCreatorSummary";
import { BILL_INPUTS } from "../bill/creator/inputs";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SwaySelect from "../forms/SwaySelect";
import SwayText from "../forms/SwayText";
import SwayTextArea from "../forms/SwayTextArea";
import SwaySpinner from "../SwaySpinner";
import BillCreatorOrganizations from "./BillCreatorOrganizations";
import BillCreatorSummaryAudio from "./BillCreatorSummaryAudio";
import BillOfTheWeekCreatorPreview from "./BillOfTheWeekCreatorPreview";
import { IDataOrganizationPosition } from "./types";

const VALIDATION_SCHEMA = Yup.object().shape({
    externalId: Yup.string().required(),
    externalVersion: Yup.string(),
    title: Yup.string().required(),
    link: Yup.string().required().url(),
    swaySummary: Yup.string(),
    sponsorExternalId: Yup.string().required(),
    localeName: Yup.string().required(),
    legislators: Yup.object().required(),
    swayAudioBucketPath: Yup.string().nullable().notRequired(),
});

type ISubmitValues = sway.IBill & {
    localeName: string;
    supporters: string[];
    opposers: string[];
    abstainers: string[];
    legislators: sway.ILegislatorBillSupport;
    organizations: IDataOrganizationPosition[];

    swayAudioBucketPath?: string;
    swayAudioByline?: string;

    introducedDate: string | Date | undefined;
    votedate: string | Date | undefined;
    houseVoteDate: string | Date | undefined;
    senateVoteDate: string | Date | undefined;

    positions: {
        [organizationName: string]: {
            name: string;
            iconPath: string;
            positions: {
                [billFirestoreId: string]: {
                    billFirestoreId: string;
                    support: boolean;
                    summary: string;
                };
            };
        };
    };
};

const DEFAULT_BILL_ID = "new-botw";
const DEFAULT_LEGISLATORS = [] as sway.ILegislator[];
const DEFAULT_ORGANIZATIONS = [] as sway.IOrganization[];
const DEFAULT_BILLS_FILTERS = [EUseBillsFilters.ORGANIZATIONS] as EUseBillsFilters[];

const BillOfTheWeekCreator: React.FC = () => {
    const makeCancellable = useCancellable();
    const summaryRef = useRef<string>("");
    const [locale] = useLocale();
    // const user = useUserWithSettingsAdmin();
    // const { isAdmin } = user;
    const isAdmin = true
    const [bills, getBills] = useBills(DEFAULT_BILLS_FILTERS);
    const [legislatorVotes, legislatorVoteLegislatorIds, getLegislatorVotes] = useLegislatorVotes();

    const [isLoading, setLoading] = useState<boolean>(false);
    const [selectedPreviousBOTWId, setSelectedPreviousBOTWId] = useState<string>(DEFAULT_BILL_ID);
    const [legislators, setLegislators] = useState<sway.ILegislator[]>(DEFAULT_LEGISLATORS);
    const [organizations, setOrganizations] = useState<sway.IOrganization[]>(DEFAULT_ORGANIZATIONS);

    // const selectedPreviousBOTW = (bills || []).find(
    //     (b) => b.bill.firestoreId === selectedPreviousBOTWId,
    // ) as sway.IBillOrgsUserVoteScore;

    const [selectedPreviousBOTW, getBill] = useBill(selectedPreviousBOTWId);
    useEffect(getBill, [getBill]);

    const previousBOTWOptions = useMemo(
        () =>
            [
                <option key={DEFAULT_BILL_ID} value={DEFAULT_BILL_ID}>
                    New Bill of the Week
                </option>,
            ].concat(
                bills.map((b) => (
                    <option
                        key={b.bill.firestoreId}
                        value={b.bill.firestoreId}
                    >{`${b.bill.externalId} - ${b.bill.title}`}</option>
                )),
            ),
        [bills],
    );

    const legislatorOptions = useMemo(
        () =>
            sortBy(
                legislators.map((l: sway.ILegislator) =>
                    toSelectOption(
                        `${titleize(l.lastName)}, ${titleize(l.firstName)} (${l.district.regionCode} - ${
                            l.district.number
                        })`,
                        l.externalId,
                    ),
                ),
                ["label"],
            ),
        [legislators],
    );
    const legislatorIds = useMemo(
        () => legislators.map((l: sway.ILegislator) => l.externalId),
        [legislators],
    );

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect - set summary ref to summary from selected bill");
        summaryRef.current = selectedPreviousBOTW?.bill?.swaySummary || "";
    }, [selectedPreviousBOTW?.bill?.swaySummary]);

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect - get bills");
        setLoading(true);
        getBills([])
            .then(() => {
                setLoading(false);
            })
            .catch((error) => {
                setLoading(false);
                handleError(error);
            });
    }, []);

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect - get legislator votes");

        if (selectedPreviousBOTW?.bill?.firestoreId && !isEmptyObject(legislatorIds)) {
            logDev("BillOfTheWeekCreator.useEffect - set legislator votes for selected bill");
            setLoading(true);
            getLegislatorVotes(legislatorIds, selectedPreviousBOTW.bill.firestoreId)
                .then(() => {
                    setLoading(false);
                })
                .catch((error) => {
                    setLoading(false);
                    handleError(error);
                });
        }
    }, [getLegislatorVotes, legislatorIds, selectedPreviousBOTW?.bill.firestoreId]);

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect.LOAD");

        if (!isAdmin) {
            logDev("BillOfTheWeekCreator.useEffect - no admin, skip initializing");
            return;
        }

        if (!locale) {
            // setLocale(DEFAULT_LOCALE);
            logDev("BillOfTheWeekCreator.useEffect - set locale to LOCALES.first");
            return;
        }

        setLoading(true);

        const getOrganizations = async (): Promise<sway.IOrganization[]> => {
            if (!locale?.name) return [];

            return []
            // const orgs = []
            // logDev("BillOfTheWeekCreator.useEffect - get organizations");
            // if (!orgs) return [];
            // return orgs;
        };

        const getLegislators = async () => {
            if (!locale?.name) return [];
            logDev("BillOfTheWeekCreator.useEffect - get legislators for locale -", locale.name);
            return [];
            // const _legislators: (sway.ILegislator | undefined)[] = (await swayFireClient(locale)
            //     .legislators()
            //     .list()) as sway.ILegislator[];
            // return _legislators.filter(Boolean) as sway.ILegislator[];
        };

        const promise = makeCancellable(Promise.all([getOrganizations(), getLegislators()]), () =>
            logDev("BillOfTheWeekCreator.useEffect - canceled initialization"),
        );

        promise
            .then(([orgs, legs]) => {
                logDev("BillOfTheWeekCreator.useEffect - set organizations and legislators state");
                setLoading(false);
                setOrganizations(orgs);
                setLegislators(legs);
            })
            .catch((error) => {
                setLoading(false);
                handleError(error);
            });
    }, [isAdmin, locale?.name]);

    const getFirestoreId = useCallback((values: sway.IBill) => {
        if (!values.firestoreId) {
            if (!values.externalVersion) {
                return values.externalId;
            }
            return `${values.externalId}v${values.externalVersion}`;
        }
        return values.firestoreId;
    }, []);

    const reduceLegislatorVotes = useCallback(
        (
            externalLegislatorIds: string[],
            support: sway.TLegislatorSupport,
        ): sway.ILegislatorBillSupport => {
            return externalLegislatorIds.reduce(
                (
                    sum: {
                        [externalLegislatorId: string]: sway.TLegislatorSupport;
                    },
                    externalLegislatorId: string,
                ) => {
                    sum[externalLegislatorId] = support;
                    return sum;
                },
                {},
            );
        },
        [],
    );

    const handleSubmit = (
        values: ISubmitValues,
        { setSubmitting }: { setSubmitting: (_isSubmitting: boolean) => void },
    ) => {
        logDev(
            "BillOfTheWeekCreator.handleSubmit - SUBMITTING - new bill of the week - VALUES + SUMMARY REF",
            {
                values,
                summaryRef: summaryRef.current,
            },
        );
        if (!isAdmin) return;

        try {
            values.firestoreId = getFirestoreId(values);
            values.localeName = locale.name;
            values.swaySummary = summaryRef.current;
            values.summaries = {
                sway: summaryRef.current,
                swayAudioBucketPath: values.swayAudioBucketPath,
                swayAudioByline: values.swayAudioByline,
            } as sway.ISwayBillSummaries;

            values.positions = values.organizations.reduce((sum, o) => {
                // @ts-ignore
                sum[o.value] = {
                    name: o.value,
                    iconPath: o?.iconPath || "",
                    positions: {
                        [values.firestoreId]: {
                            billFirstoreId: values.firestoreId,
                            support: o.support || false,
                            summary: o.position,
                        },
                    },
                };
                return sum;
            }, {});
            logDev("BillOfTheWeekCreator.handleSubmit - ORGANIZATION POSITIONS -", {
                // @ts-ignore
                positions: values.positions,
            });

            if (!values.swaySummary) {
                notify({
                    level: "warning",
                    title: "Sway summary is required.",
                });
                setSubmitting(false);
                return;
            }

            if (!legislators.map((l) => l.externalId).includes(values.sponsorExternalId)) {
                notify({
                    level: "error",
                    title: "Invalid Sponsor",
                    message: "Sponsor is not a valid legislator. Wrong locale?.",
                });
                setSubmitting(false);
                return;
            }

            const concatted = values.supporters.concat(values.opposers).concat(values.abstainers);
            if (concatted.length > legislators.length) {
                const dupes = concatted.filter((id: string, index: number) => {
                    return concatted.lastIndexOf(id) !== index;
                });
                notify({
                    level: "error",
                    title: "Duplicate Legislator Positions",
                    message: `Legislators - ${dupes.join(
                        ", ",
                    )} - are duplicated in multiple positions.`,
                });
                logDev(
                    "BillOfTheWeekCreator.handleSubmit - DUPLICATE LEGISLATOR POSITION -",
                    dupes,
                );
                setSubmitting(false);
                return;
            }

            values.legislators = {
                ...reduceLegislatorVotes(values.supporters, Support.For),
                ...reduceLegislatorVotes(values.opposers, Support.Against),
                ...reduceLegislatorVotes(values.abstainers, Support.Abstain),
            };
            if (
                !isCongressLocale(locale) &&
                Object.keys(values.legislators).length !== legislators.length
            ) {
                const valueIds = Object.keys(values.legislators);
                const missing = legislators.filter((l) => !valueIds.includes(l.externalId));
                notify({
                    level: values.votedate ? "error" : "warning",
                    title: values.votedate
                        ? "Legislators Missing"
                        : "IGNORING Missing Legislators - No Vote Date",
                    message: `Legislators - ${missing
                        .map((l) => l.externalId)
                        .join(", ")} - are missing support.`,
                });
                logDev("BillOfTheWeekCreator.handleSubmit - MISSING LEGISLATOR -", missing);
                setSubmitting(false);
                if (values.votedate) {
                    return;
                }
            }

            logDev("BillOfTheWeekCreator.handleSubmit - VALUES", values);

            // setSubmitting(true);
            // const setter = httpsCallable(functions, CLOUD_FUNCTIONS.createBillOfTheWeek);
            // setter(values)
            //     .then((response) => {
            //         if (
            //             (response as HttpsCallableResult<sway.ICloudFunctionResponse>).data.success
            //         ) {
            //             notify({
            //                 level: "success",
            //                 title: "Bill of the Week Created.",
            //                 message: "Created bill of the week",
            //             });
            //         } else {
            //             notify({
            //                 level: "error",
            //                 title: "Error",
            //                 message: "Failed to create bill of the week",
            //             });
            //         }
            //         setSubmitting(false);
            //     })
            //     .catch((error: Error) => {
            //         logDev(
            //             "BillOfTheWeekCreator.handleSubmit - ERROR - setting bill of the week in firebase",
            //         );
            //         handleError(error);
            //         setSubmitting(false);
            //     });
        } catch (e) {
            console.error(e);
            setSubmitting(false);
        }
    };

    const generateValues = useCallback((field: sway.IFormField, values: ISubmitValues) => {
        if (field.component === "generatedText" && field.generateFields) {
            return field.generateFields
                .map((fieldname: string) => (values as Record<string, any>)[fieldname])
                .join(field.joiner || " ");
        }
        return "";
    }, []);

    const assignPossibleValues = (
        field: sway.IFormField,
        values?: ISubmitValues,
    ): sway.TOption[] => {
        if (field.name === "sponsorExternalId") {
            return legislatorOptions;
        } else if (field.name === "chamber") {
            if (isCongressLocale(locale)) {
                return [toSelectOption("house", "house"), toSelectOption("senate", "senate")];
            } else {
                return [toSelectOption("council", "council")];
            }
        } else if (field.name === "organizations") {
            return organizations.map((o) => ({
                label: o.name,
                value: o.name,
                iconPath: o.iconPath,
                support: get(o.positions, selectedPreviousBOTWId),
            }));
        } else if (["supporters", "opposers", "abstainers"].includes(field.name)) {
            const selectedSupporterIds = get(values, "supporters") || [];
            const selectedOpposerIds = get(values, "opposers") || [];
            const selectedAbstainerIds = get(values, "abstainers") || [];
            const selected = selectedSupporterIds
                .concat(selectedOpposerIds)
                .concat(selectedAbstainerIds);

            return legislatorOptions.filter((o) => !selected.includes(o.value as string));
        } else {
            return field.possibleValues || [];
        }
    };

    const handleSetLocale = useCallback((_fieldName: string, newLocaleName: string) => {
        // const newLocale = LOCALES.find((l) => l.name === newLocaleName);
        // if (!newLocale) {
        //     notify({
        //         level: "error",
        //         title: "Error Changing Locale",
        //         message: "Sorry about that. We're looking into it.",
        //     });
        //     return;
        // }
        // logDev("handleSetLocale.newLocale", _fieldName, newLocaleName);
        // setLocale(newLocale);
    }, []);

    const getDateFromString = useCallback((date?: string) => {
        if (!date) {
            return new Date();
        } else {
            const d = new Date(date);
            // eslint-disable-next-line
            if (d.toString() == "Invalid Date") {
                return new Date();
            } else {
                return d;
            }
        }
    }, []);

    const initialBill = {
        externalId: selectedPreviousBOTW?.bill?.externalId?.trim() || "",
        externalVersion: selectedPreviousBOTW?.bill?.externalVersion?.trim() || "",
        firestoreId: selectedPreviousBOTW?.bill?.firestoreId?.trim() || "",
        title: selectedPreviousBOTW?.bill?.title?.trim() || "",
        link: selectedPreviousBOTW?.bill?.link?.trim() || "",
        sponsorExternalId: selectedPreviousBOTW?.bill?.sponsorExternalId?.trim() || "",
        chamber:
            selectedPreviousBOTW?.bill?.chamber || (isCongressLocale(locale) ? "house" : "council"),
        level: selectedPreviousBOTW?.bill?.level?.trim() || ESwayLevel.Local,
        active: selectedPreviousBOTW?.bill?.active || true,
        swaySummary:
            selectedPreviousBOTW?.bill?.swaySummary?.trim() ||
            selectedPreviousBOTW?.bill?.summaries?.sway?.trim() ||
            "",
        swayAudioBucketPath:
            selectedPreviousBOTW?.bill?.summaries?.swayAudioBucketPath?.trim() || "",
        swayAudioByline: selectedPreviousBOTW?.bill?.summaries?.swayAudioByline?.trim() || "",
        introducedDate: getDateFromString(selectedPreviousBOTW?.bill?.introducedDate),
        votedate: getDateFromString(selectedPreviousBOTW?.bill.votedate),
        houseVoteDate: isCongressLocale(locale)
            ? getDateFromString(selectedPreviousBOTW?.bill.houseVoteDate)
            : undefined,
        senateVoteDate: isCongressLocale(locale)
            ? getDateFromString(selectedPreviousBOTW?.bill.senateVoteDate)
            : undefined,
        category: selectedPreviousBOTW?.bill?.category?.trim(),
        status: selectedPreviousBOTW?.bill?.status?.trim(),

        summaries: selectedPreviousBOTW?.bill.summaries || {},
        score: selectedPreviousBOTW?.bill.score || {},

        isTweeted: selectedPreviousBOTW?.bill.isTweeted,
        isInitialNotificationsSent: selectedPreviousBOTW?.bill.isInitialNotificationsSent,

        relatedBillIds: selectedPreviousBOTW?.bill.relatedBillIds,

        supporters: legislatorVotes
            ? legislatorVoteLegislatorIds.filter(
                  (key) =>
                      legislatorVotes[key] && legislatorVotes[key]?.toLowerCase() === Support.For,
              )
            : [],
        opposers: legislatorVotes
            ? legislatorVoteLegislatorIds.filter(
                  (key) =>
                      legislatorVotes[key] &&
                      legislatorVotes[key]?.toLowerCase() === Support.Against,
              )
            : [],
        abstainers: legislatorVotes
            ? legislatorVoteLegislatorIds.filter(
                  (key) =>
                      legislatorVotes[key] &&
                      legislatorVotes[key]?.toLowerCase() === Support.Abstain,
              )
            : [],

        organizations:
            selectedPreviousBOTW?.organizations?.map((o) => {
                return {
                    support: !!get(o, `positions.${selectedPreviousBOTWId}.support`) || false,
                    position: get(o, `positions.${selectedPreviousBOTWId}.summary`) || "",
                    value: o.name,
                    label: o.name,
                    iconPath: o.iconPath || "",
                };
                // support?: boolean;
                // position: string;
                // label: string;
                // value: string;
                // iconPath: string;
            }) || [],

        positions: (selectedPreviousBOTW?.organizations || []).reduce((sum, org) => {
            return {
                ...sum,
                [org.name]: {
                    name: org.name,
                    iconPath: org.iconPath || "",
                    positions: {
                        [selectedPreviousBOTWId]: {
                            billFirestoreId: selectedPreviousBOTWId,
                            support:
                                !!get(org, `positions.${selectedPreviousBOTWId}.support`) || false,
                            summary: get(org, `positions.${selectedPreviousBOTWId}.summary`) || "",
                        },
                    },
                },
            };
        }, {}),

        localeName: locale.name,

        legislators: legislatorVotes,
    };

    logDev("BillOfTheWeekCreator.selectedPreviousBOTW.initialBill", {
        selectedPreviousBOTW,
        initialBill,
    });

    const { initialSupporters, initialOpposers, initialAbstainers } = useMemo(() => {
        const _initialSupporters = [] as string[];
        const _initialOpposers = [] as string[];
        const _initialAbstainers = [] as string[];

        for (const legislatorExternalId of legislatorVoteLegislatorIds) {
            const support = legislatorVotes[legislatorExternalId];
            if (support === "for") {
                _initialSupporters.push(legislatorExternalId);
            } else if (support === "against") {
                _initialOpposers.push(legislatorExternalId);
            } else {
                _initialAbstainers.push(legislatorExternalId);
            }
        }
        return {
            initialSupporters: _initialSupporters,
            initialOpposers: _initialOpposers,
            initialAbstainers: _initialAbstainers,
        };
    }, [legislatorVotes, legislatorVoteLegislatorIds]);

    const initialValues = {
        ...initialBill,
        localeName: CONGRESS_LOCALE_NAME,
        organizations:
            (
                selectedPreviousBOTW?.organizations ||
                // @ts-ignore
                selectedPreviousBOTW?.bill?.organizations ||
                []
            )
                // @ts-ignore
                .reduce((sum, o) => {
                    const firestoreId = selectedPreviousBOTW?.bill?.firestoreId;
                    return sum.concat({
                        label: o.name,
                        value: o.name,
                        position: get(o, `positions.${firestoreId}.summary`) || "",
                        support: get(o, `positions.${firestoreId}.support`) || false,
                        iconPath: o.iconPath || "",
                    });
                }, [] as IDataOrganizationPosition[]) || [],
        legislators: legislatorVotes,
        supporters: initialSupporters,
        opposers: initialOpposers,
        abstainers: initialAbstainers,
        swayAudioBucketPath: "",
        swayAudioByline: "",
    } as ISubmitValues;

    const isRenderPositionsSelects = useCallback(
        (field: sway.IFormField) => {
            if (["supporters", "opposers", "abstainers"].includes(field.name)) {
                return locale.name !== CONGRESS_LOCALE_NAME;
            } else {
                return true;
            }
        },
        [locale.name],
    );

    const renderFields = (formik: FormikProps<ISubmitValues>) => {
        const { values, touched, errors, setFieldValue, setTouched } = formik;
        if (!isEmptyObject(errors)) {
            logDev("BillOfTheWeekCreator.renderFields - ERRORS", errors);
        }

        logDev("BillOfTheWeekCreator.renderFields - VALUES -", values);

        const handleSetTouched = (fieldname: string) => {
            if ((touched as Record<string, any>)[fieldname]) return;
            setTouched({
                ...touched,
                [fieldname]: true,
            }).catch(console.error);
        };

        const errorMessage = (fieldname: string): string => {
            if (!fieldname || !errors || !(touched as Record<string, any>)[fieldname]) return "";

            const error = get(errors, fieldname);
            if (!error) return "";

            if (Array.isArray(error)) {
                return (error as string[]).find((e) => e === fieldname) || "";
            } else {
                return error as string;
            }
        };

        const render = [] as React.ReactNode[];
        let i = 0;
        while (i < BILL_INPUTS.length) {
            const fieldGroup = BILL_INPUTS[i];

            const row = [];
            for (const field of fieldGroup) {
                const generatedValue = generateValues(field, values);

                const { component } = field;

                if (
                    ["houseVoteDate", "senateVoteDate"].includes(field.name) &&
                    !isCongressLocale(locale)
                ) {
                    continue;
                }

                if (["text", "generatedText"].includes(component)) {
                    const value = component === "text" ? (values as Record<string, any>)[field.name] : generatedValue;

                    row.push(
                        <div key={field.name} className="col">
                            <SwayText
                                field={{
                                    ...field,
                                    disabled: Boolean(
                                        field.disabled ||
                                            (field.disableOn?.(locale)),
                                    ),
                                }}
                                value={value}
                                error={errorMessage(field.name)}
                                helperText={field.helperText}
                            />
                        </div>,
                    );
                } else if (component === "select") {
                    if (field.name === "organizations") {
                        field.possibleValues = assignPossibleValues(field);
                        row.push(
                            <div key={field.name} className="col-12 py-4">
                                <BillCreatorOrganizations
                                    field={{
                                        ...field,
                                        disabled: Boolean(
                                            field.disabled ||
                                                (field.disableOn?.(locale)),
                                        ),
                                    }}
                                    organizations={(values as Record<string, any>)[field.name]}
                                    touched={!!(touched as Record<string, any>)[field.name]}
                                    error={errors[field.name] as string | undefined}
                                    setFieldValue={setFieldValue}
                                    handleSetTouched={handleSetTouched}
                                    billFirestoreId={getFirestoreId(values)}
                                />
                            </div>,
                        );
                    } else if (field.name === "localeName") {
                        row.push(
                            <div key={field.name} className="col">
                                <SwaySelect
                                    field={field}
                                    error={errorMessage(field.name)}
                                    handleSetTouched={() => null}
                                    setFieldValue={(fname, fvalue) => {
                                        handleSetLocale(fname, fvalue);
                                        setFieldValue(fname, fvalue).catch(console.error);
                                    }}
                                    value={toSelectOption(
                                        toFormattedLocaleName(values.localeName),
                                        values.localeName,
                                    )}
                                    helperText={field.helperText}
                                />
                            </div>,
                        );
                    } else {
                        field.possibleValues = assignPossibleValues(field, values);
                        const val = (values as Record<string, any>)[field.name];
                        const { name } = field;
                        const value = Array.isArray(val)
                            ? val.map((v) => toSelectOption(v, v))
                            : val
                            ? toSelectOption(val as string, val as string)
                            : toSelectOption(`Select ${field.label.toLowerCase()}...`, "");

                        logDev("SwaySelect.value", { name, val, value });
                        row.push(
                            <Form.Group key={name} controlId={name} className="col">
                                {field.label && (
                                    <Form.Label className="bold">
                                        {field.label}
                                        {field.isRequired ? " *" : " (Optional)"}
                                    </Form.Label>
                                )}
                                <Select
                                    name={name}
                                    styles={REACT_SELECT_STYLES}
                                    options={field.possibleValues as Options<sway.TOption>}
                                    isMulti={Boolean(field.multi)}
                                    isDisabled={
                                        !isRenderPositionsSelects(field) ||
                                        field.disabled ||
                                        (field.disableOn?.(locale))
                                    }
                                    value={value}
                                    onChange={(changed) => {
                                        if (field.multi) {
                                            setFieldValue(
                                                name,
                                                (changed as MultiValue<sway.TOption>).map(
                                                    (c) => c.value,
                                                ),
                                            ).catch(console.error);
                                        } else {
                                            setFieldValue(
                                                name,
                                                (changed as SingleValue<sway.TOption>)?.value,
                                            ).catch(console.error);
                                        }
                                    }}
                                    closeMenuOnSelect={
                                        !["supporters", "opposers", "abstainers"].includes(name)
                                    }
                                />
                            </Form.Group>,
                        );
                    }
                } else if (field.name === "swaySummary") {
                    row.push(
                        <Form.Group key={field.name} controlId={field.name} className="col">
                            <Form.Label className="bold">
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <BillCreatorSummary
                                ref={summaryRef}
                                field={{
                                    ...field,
                                    disabled: Boolean(
                                        field.disabled ||
                                            (field.disableOn?.(locale)),
                                    ),
                                }}
                            />
                            <BillCreatorSummaryAudio setFieldValue={setFieldValue} />
                        </Form.Group>,
                    );
                } else if (field.name === "swaySummaryPreview") {
                    // noop
                } else if (component === "textarea") {
                    row.push(
                        <Form.Group key={field.name} controlId={field.name} className="col">
                            <Form.Label className="bold">
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <SwayTextArea
                                field={{
                                    ...field,
                                    disabled: Boolean(
                                        field.disabled ||
                                            (field.disableOn?.(locale)),
                                    ),
                                }}
                                value={(values as Record<string, any>)[field.name]}
                                error={errorMessage(field.name)}
                                setFieldValue={setFieldValue}
                                handleSetTouched={handleSetTouched}
                                helperText={field.helperText}
                                rows={field.rows}
                            />
                        </Form.Group>,
                    );
                } else if (component === "date") {
                    row.push(
                        <Form.Group key={field.name} controlId={field.name} className="col">
                            <Form.Label className="bold">
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <DatePicker
                                className="form-control"
                                placeholderText={"Select date..."}
                                disabled={
                                    field.disabled || (field.disableOn?.(locale))
                                }
                                minDate={(() => {
                                    const date = new Date();
                                    date.setFullYear(date.getFullYear() - 1);
                                    return date;
                                })()}
                                maxDate={(() => {
                                    const date = new Date();
                                    date.setHours(date.getHours() + 24);
                                    return date;
                                })()}
                                selected={(values as Record<string, any>)[field.name]}
                                onChange={(changed: Date) => {
                                    setFieldValue(field.name, changed).catch(console.error);
                                }}
                            />
                            {field.helperText && (
                                <div className="text-muted">{field.helperText}</div>
                            )}
                            <div className="text-danger">{errorMessage(field.name)}</div>
                        </Form.Group>,
                    );
                }
            }
            render.push(
                <div key={`row-${render.length}`} className="row my-5 border rounded p-3">
                    {row}
                </div>,
            );
            i++;
        }
        return render;
    };

    const handleChangeBill = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
        setSelectedPreviousBOTWId(event?.target?.value || DEFAULT_BILL_ID);
    }, []);

    if (!isAdmin || !locale) {
        logDev("BillOfTheWeekCreator - no admin OR no locale - render null");
        return null;
    }

    return (
        <div className="col">
            {isLoading && <FullScreenLoading message="Loading..." />}
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
                                <Form.Group controlId="previoiusBotwId">
                                    <Form.Label className="bold">
                                        Previous Bill of the Day
                                    </Form.Label>
                                    <Form.Control
                                        as="select"
                                        className="w-100 pointer"
                                        value={selectedPreviousBOTWId}
                                        onChange={handleChangeBill}
                                    >
                                        {previousBOTWOptions}
                                    </Form.Control>
                                </Form.Group>
                                <hr />
                                {renderFields(formik)}
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
                            <BillOfTheWeekCreatorPreview
                                billFirestoreId={formik.values.firestoreId || DEFAULT_BILL_ID}
                                organizations={formik.values.organizations}
                                swaySummary={summaryRef.current}
                            />
                        </>
                    );
                }}
            </Formik>
        </div>
    );
};

export default BillOfTheWeekCreator;
