import { usePage } from "@inertiajs/react";
import BillCreatorFormHeader from "app/frontend/components/admin/creator/BillCreatorFormHeader";
import { useTempStorage } from "app/frontend/components/admin/creator/hooks/useTempStorage";
import { IApiLegislatorVote, ICreatorLegislatorVotes } from "app/frontend/components/admin/creator/types";
import FormContext from "app/frontend/components/contexts/FormContext";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";
import { Support } from "app/frontend/sway_constants";
import { notify, SWAY_STORAGE, titleize } from "app/frontend/sway_utils";
import { sortBy } from "lodash";
import { useCallback, useEffect, useMemo } from "react";
import { Button, Form } from "react-bootstrap";
import { FiSave } from "react-icons/fi";
import { ISelectOption, sway } from "sway";
import { useInertiaForm } from "use-inertia-form";

const getNewLegislatorVote = (legislatorId: number, support: sway.TLegislatorSupport) =>
    ({
        legislator_id: legislatorId,
        support,
    }) as IApiLegislatorVote;

const toLegislatorSelectOption = (legislator: sway.ILegislator) => ({
    label: `${titleize(legislator.firstName)} ${titleize(legislator.lastName)} (${legislator.district.regionCode} - ${legislator.district.number})`,
    value: legislator.id,
});

const toApiLegislatorVote = (legislatorVote: sway.ILegislatorVote) => ({
    legislator_id: legislatorVote.legislatorId,
    support: legislatorVote.support,
});

const filter = (votes: IApiLegislatorVote[], legislatorId: number) =>
    votes.filter((v) => v.legislator_id !== legislatorId);

const BillCreatorLegislatorVotes = () => {
    const bill = usePage().props.bill as sway.IBill;
    const legislators = usePage().props.legislators as sway.ILegislator[];
    const legislatorVotes = usePage().props.legislatorVotes as sway.ILegislatorVote[];
    const legislatorOptions = useMemo(
        () => sortBy(legislators ?? [], (l) => l.district.regionCode).map(toLegislatorSelectOption),
        [legislators],
    ) as ISelectOption[];

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

    const defaultValues = useMemo(() => {
        return legislatorVotes.reduce(
            (sum, item) => {
                if (!item.support) return sum;

                return {
                    ...sum,
                    [item.support]: [...sum[item.support], toApiLegislatorVote(item)],
                };
            },
            {
                [Support.For]: [],
                [Support.Against]: [],
                [Support.Abstain]: [],
            },
        );
    }, [legislatorVotes]) as ICreatorLegislatorVotes;

    const form = useInertiaForm<ICreatorLegislatorVotes>(defaultValues);
    const { data, setData, post, transform } = form;
    const { storage, onBlur, blurredFieldName } = useTempStorage(
        SWAY_STORAGE.Local.BillOfTheWeek.LegislatorVotes,
        data,
    );

    const onChange = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const [_legislatorId, support] = e.target.id.split("-") as [string, sway.TLegislatorSupport];
            const legislatorId = Number(_legislatorId);

            let newFor = filter(data.FOR, legislatorId);
            let newAgainst = filter(data.AGAINST, legislatorId);
            let newAbstain = filter(data.ABSTAIN, legislatorId);

            if (support === Support.For) {
                newFor = newFor.concat(getNewLegislatorVote(legislatorId, Support.For));
            } else if (support === Support.Against) {
                newAgainst = newAgainst.concat(getNewLegislatorVote(legislatorId, Support.Against));
            } else if (support === Support.Abstain) {
                newAbstain = newAbstain.concat(getNewLegislatorVote(legislatorId, Support.Abstain));
            }

            setData(Support.For, newFor);
            setData(Support.Against, newAgainst);
            setData(Support.Abstain, newAbstain);
        },
        [data, setData],
    );

    const onSubmit = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();

            if (!bill.id) {
                notify({
                    level: "error",
                    title: "Click Save on the Details and Summary tab before clicking save here.",
                });
                return;
            }

            // @ts-expect-error - Missing 'FOR, AGAINST, ABSTAIN'
            transform((formData) => {
                return {
                    bill_id: bill.id,
                    legislator_votes: formData.FOR.concat(formData.AGAINST).concat(formData.ABSTAIN),
                };
            });

            post("/legislator_votes", { preserveScroll: true, async: true });
        },
        [bill.id, post, transform],
    );

    return (
        <FormContext.Provider value={form}>
            <Form onSubmit={onSubmit}>
                <BillCreatorFormHeader form={form} storage={storage} blurredFieldName={blurredFieldName} />

                <div className="col">
                    {legislatorOptions?.map((option, index) => {
                        return (
                            <div
                                key={`legislator-votes-${index}`}
                                className={`row my-2 py-2 ${index === 0 ? "border-top mt-2" : ""} ${index % 2 === 1 ? "bg-secondary-subtle" : ""}`}
                            >
                                <div className="col-12 col-sm-6 py-2">{option.label}</div>
                                <div className="col-4 col-sm-2 py-2">
                                    <Form.Check
                                        type={"radio"}
                                        id={`${option.value}-${Support.For}`}
                                        label={<div className="pointer">{titleize(Support.For)}</div>}
                                        onChange={onChange}
                                        checked={!!data.FOR.find((v) => v.legislator_id === option.value)}
                                        className="pointer"
                                        onBlur={onBlur}
                                    />
                                </div>
                                <div className="col-4 col-sm-2 py-2">
                                    <Form.Check
                                        type={"radio"}
                                        id={`${option.value}-${Support.Against}`}
                                        label={<div className="pointer">{titleize(Support.Against)}</div>}
                                        onChange={onChange}
                                        checked={!!data.AGAINST.find((v) => v.legislator_id === option.value)}
                                        className="pointer"
                                        onBlur={onBlur}
                                    />
                                </div>
                                <div className="col-4 col-sm-2 py-2">
                                    <Form.Check
                                        type={"radio"}
                                        id={`${option.value}-${Support.Abstain}`}
                                        label={<div className="pointer">{titleize(Support.Abstain)}</div>}
                                        onChange={onChange}
                                        checked={!!data.ABSTAIN.find((v) => v.legislator_id === option.value)}
                                        className="pointer"
                                        onBlur={onBlur}
                                    />
                                </div>
                            </div>
                        );
                    })}
                </div>
                <Button disabled={form.processing} variant="primary" size="lg" type="submit" className="p-5 w-100 my-5">
                    <FiSave />
                    &nbsp;Save Legislator Votes
                </Button>
            </Form>
        </FormContext.Provider>
    );
};

export default BillCreatorLegislatorVotes;
