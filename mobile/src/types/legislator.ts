import type { LegislatorRecord } from "../hooks/useLegislators";

// @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Historical repair explanations]]
export interface IHistoricalScoreExplanation {
    title: string;
    body: string;
    delta: number | null;
    score_type: string;
}

export interface IAgreeableScore {
    count_agreed?: number | string;
    count_disagreed?: number | string;
    count_no_legislator_vote?: number | string;
    count_legislator_abstained?: number | string;
}

// @lat: [[voter-privacy-threshold#Legislator scores are sent as percentages]]
export interface IGroupAgreeableScore {
    comparison_suppressed?: boolean | null;
    agreed_percent?: number | null;
    disagreed_percent?: number | null;
    no_legislator_vote_percent?: number | null;
    legislator_abstained_percent?: number | null;
    voter_agreement_percent?: number | null;
}

// @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]
export interface ILegislatorTermEntry {
    id: number;
    session_label: string;
    term_start_year: number;
    term_end_year: number;
    began_on: string | null;
    ended_on: string | null;
    district_name: string | null;
    is_executive: boolean;
    active: boolean;
    district_score: IGroupAgreeableScore | null;
    locale_score: IGroupAgreeableScore | null;
    user_score: IAgreeableScore | null;
    correction_explanation: IHistoricalScoreExplanation | null;
}

export interface IAgreementCalc {
    displayPct: string;
    agreed: number;
    disagreed: number;
    noVote: number;
    abstained: number;
    total: number;
}

export function calculateAgreement(score: IAgreeableScore | null | undefined): IAgreementCalc {
    if (!score) {
        return {
            displayPct: "--%",
            agreed: 0,
            disagreed: 0,
            noVote: 0,
            abstained: 0,
            total: 0,
        };
    }
    const agreed = Number(score.count_agreed || 0);
    const disagreed = Number(score.count_disagreed || 0);
    const noVote = Number(score.count_no_legislator_vote || 0);
    const abstained = Number(score.count_legislator_abstained || 0);
    const total = agreed + disagreed;

    if (total === 0) {
        return {
            displayPct: "--%",
            agreed,
            disagreed,
            noVote,
            abstained,
            total: 0,
        };
    }

    const pct = Math.round((agreed / total) * 100);
    return {
        displayPct: `${pct}%`,
        agreed,
        disagreed,
        noVote,
        abstained,
        total,
    };
}

// @lat: [[legislator-botm-record#Bill of the Month voting record on the legislator page]]
export interface ILegislatorBillOfTheMonthVote {
    bill_id: number;
    external_id: string;
    title: string;
    scheduled_release_date_utc: string;
    status: string | null;
    legislator_vote: "FOR" | "AGAINST" | "ABSTAIN" | null;
    user_vote: "FOR" | "AGAINST" | null;
    alignment: "agreed" | "disagreed" | null;
}

export interface Legislator extends LegislatorRecord {
    terms?: ILegislatorTermEntry[];
    bill_of_the_month_votes?: ILegislatorBillOfTheMonthVote[];
}

export type ILegislator = Legislator;

export interface ILegislatorTermCardProps {
    term: ILegislatorTermEntry;
    legislatorName?: string;
    legislator?: LegislatorRecord | Legislator;
    fallbackDistrictName?: string | null;
    isLoggedIn?: boolean;
    onPressExplanation?: (explanation: IHistoricalScoreExplanation, term: ILegislatorTermEntry) => void;
    onSignInPress?: () => void;
}

export interface IHistoricalRepairModalProps {
    explanation: IHistoricalScoreExplanation | null;
    term: ILegislatorTermEntry | null;
    legislatorName: string;
    visible: boolean;
    onClose: () => void;
}

export interface IGroupAgreementCalc {
    suppressed: boolean;
    displayPct: string;
    agreedPct: number;
    disagreedPct: number;
    noVotePct: number;
}

// @lat: [[voter-privacy-threshold#The mobile legislator screens draw percentages or the placeholder]]
export function calculateGroupAgreement(score: IGroupAgreeableScore | null | undefined): IGroupAgreementCalc {
    const headline = score?.voter_agreement_percent;
    return {
        suppressed: score?.comparison_suppressed !== false,
        displayPct: headline === null || headline === undefined ? "--%" : `${headline}%`,
        agreedPct: score?.agreed_percent ?? 0,
        disagreedPct: score?.disagreed_percent ?? 0,
        noVotePct: score?.no_legislator_vote_percent ?? 0,
    };
}
