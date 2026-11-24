import type { sway } from "sway";

const percentOf = (count: number, total: number) => Math.round((count / total) * 100);

export const suppressedGroupScore = (counters: sway.scoring.IAgreeable): sway.scoring.IGroupAgreeable => ({
    ...counters,
    comparison_suppressed: true,
    agreed_percent: null,
    disagreed_percent: null,
    no_legislator_vote_percent: null,
    legislator_abstained_percent: null,
});

export const groupScore = (counters: sway.scoring.IAgreeable): sway.scoring.IGroupAgreeable => {
    const total =
        counters.count_agreed +
        counters.count_disagreed +
        counters.count_no_legislator_vote +
        counters.count_legislator_abstained;
    if (total === 0) return suppressedGroupScore(counters);

    return {
        ...counters,
        comparison_suppressed: false,
        agreed_percent: percentOf(counters.count_agreed, total),
        disagreed_percent: percentOf(counters.count_disagreed, total),
        no_legislator_vote_percent: percentOf(counters.count_no_legislator_vote, total),
        legislator_abstained_percent: percentOf(counters.count_legislator_abstained, total),
    };
};
