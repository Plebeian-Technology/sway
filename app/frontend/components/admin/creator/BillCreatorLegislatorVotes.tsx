import { router, usePage, useForm } from "@inertiajs/react";
import BillCreatorLegislatorVotesHeader from "app/frontend/components/admin/creator/legislator-votes/BillCreatorLegislatorVotesHeader";
import BillCreatorLegislatorVotesRow from "app/frontend/components/admin/creator/legislator-votes/BillCreatorLegislatorVotesRow";
import {
    filterOut,
    legislatorDisplayName,
    toApiLegislatorVote,
} from "app/frontend/components/admin/creator/legislator-votes/utils";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { ICreatorLegislatorVotes } from "app/frontend/components/admin/creator/types";
import { Support, type TSupport } from "app/frontend/sway_constants";
import { notify } from "app/frontend/sway_utils";
import { sortBy } from "lodash";
import { Save } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { sway } from "sway";
import { Button } from "app/frontend/components/ui/button";

interface IPageProps {
    bill?: sway.IBill;
    legislators?: sway.ILegislator[];
    legislator_votes?: sway.ILegislatorVote[];
    legislator_votes_refreshed_at?: string | null;
    legislator_votes_source?: string | null;
    [key: string]: unknown;
}

// @lat: [[bill-creator-legislator-votes-form#Why it keeps its own useForm() instead of sharing SwayFormContext]]
// @lat: [[bill-creator-legislator-votes-form#Why REFUSAL_FALLBACK only applies when the server sent no message]]
const REFUSAL_FALLBACK = "Could not save legislator votes.";

const BillCreatorLegislatorVotes: React.FC = () => {
    const page = usePage<IPageProps>();
    const bill = page.props.bill;
    const legislators = useMemo(() => page.props.legislators ?? [], [page.props.legislators]);
    const legislator_votes = useMemo(() => page.props.legislator_votes ?? [], [page.props.legislator_votes]);

    // @lat: [[bill-creator-legislator-votes-form#Why there is no ?saved= check for the create/update toast]]
    // @lat: [[bill-creator-legislator-votes-form#Why legislator_votes_refreshed_at gets its own notify()]]
    const legislatorVotesRefreshedAt = page.props.legislator_votes_refreshed_at ?? null;
    const legislatorVotesSource = page.props.legislator_votes_source ?? null;
    useEffect(() => {
        if (!legislatorVotesRefreshedAt || !legislatorVotesSource) return;
        notify({
            level: "info",
            title: `Legislator votes refreshed at ${legislatorVotesRefreshedAt} from ${legislatorVotesSource}.`,
        });
    }, [legislatorVotesRefreshedAt, legislatorVotesSource]);

    const defaultValues = useMemo<ICreatorLegislatorVotes>(() => {
        return legislator_votes.reduce<ICreatorLegislatorVotes>(
            (acc, item) => {
                if (!item.support) return acc;
                const bucket = item.support as TSupport;
                return {
                    ...acc,
                    [bucket]: [...acc[bucket], toApiLegislatorVote(item)],
                };
            },
            {
                [Support.For]: [],
                [Support.Against]: [],
                [Support.Abstain]: [],
            },
        );
    }, [legislator_votes]);

    const { data, setData } = useForm<ICreatorLegislatorVotes>(defaultValues);
    const [submitting, setSubmitting] = useState<boolean>(false);

    const sortedLegislators = useMemo(
        () => sortBy(legislators, (l) => legislatorDisplayName(l).toLowerCase()),
        [legislators],
    );

    // @lat: [[bill-creator-legislator-votes-form#Why supportByLegislator is built as a single-pass lookup map]]
    const supportByLegislator = useMemo(() => {
        const map = new Map<number, TSupport>();
        data.FOR.forEach((v) => map.set(v.legislator_id, Support.For));
        data.AGAINST.forEach((v) => map.set(v.legislator_id, Support.Against));
        data.ABSTAIN.forEach((v) => map.set(v.legislator_id, Support.Abstain));
        return map;
    }, [data]);

    // @lat: [[bill-creator-legislator-votes-form#Why onSelectSupport uses the setData(prev => ...) form]]
    const onSelectSupport = useCallback(
        (legislator_id: number, support: TSupport) => {
            setData((prev) => {
                const newFor = filterOut(prev.FOR, legislator_id);
                const newAgainst = filterOut(prev.AGAINST, legislator_id);
                const newAbstain = filterOut(prev.ABSTAIN, legislator_id);

                return {
                    [Support.For]: support === Support.For ? [...newFor, { legislator_id, support }] : newFor,
                    [Support.Against]:
                        support === Support.Against ? [...newAgainst, { legislator_id, support }] : newAgainst,
                    [Support.Abstain]:
                        support === Support.Abstain ? [...newAbstain, { legislator_id, support }] : newAbstain,
                };
            });
        },
        [setData],
    );

    const onSubmit = useCallback(
        (e: React.SubmitEvent<HTMLFormElement>) => {
            e.preventDefault();
            if (!bill?.id) {
                notify({
                    level: "error",
                    title: "Click Save on the Details and Summary tab before saving votes.",
                });
                return;
            }
            const legislator_votes_payload = data.FOR.concat(data.AGAINST).concat(data.ABSTAIN);
            router.post(
                "/legislator_votes",
                {
                    bill_id: bill.id,
                    legislator_votes: legislator_votes_payload,
                },
                {
                    preserveScroll: true,
                    onStart: () => setSubmitting(true),
                    onFinish: () => setSubmitting(false),
                    // @lat: [[bill-creator-legislator-votes-form#Why the submit handler needs an explicit onError]]
                    onError: (errors) => notifyServerRefusal(errors, "legislator_votes", REFUSAL_FALLBACK),
                },
            );
        },
        [bill, data],
    );

    if (sortedLegislators.length === 0) {
        return (
            <p className="py-6 italic text-sm text-muted-foreground">No legislators available for this locale yet.</p>
        );
    }

    return (
        <form onSubmit={onSubmit} className="flex flex-col gap-4 py-4">
            <div className="relative w-full overflow-x-auto rounded-lg border-neo border-border-strong bg-card shadow-neo">
                <BillCreatorLegislatorVotesHeader />

                {sortedLegislators.map((legislator) => (
                    <BillCreatorLegislatorVotesRow
                        key={`legislator-row-${legislator.id}`}
                        legislator={legislator}
                        current={supportByLegislator.get(legislator.id) ?? ""}
                        onSelectSupport={onSelectSupport}
                    />
                ))}
            </div>

            <div className="flex justify-center">
                <Button type="submit" size="lg" disabled={submitting} className="min-h-11 w-full max-w-lg">
                    <Save aria-hidden />
                    &nbsp;Save Legislator Votes
                </Button>
            </div>
        </form>
    );
};

export default BillCreatorLegislatorVotes;
