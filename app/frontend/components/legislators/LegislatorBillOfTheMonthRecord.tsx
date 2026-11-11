import BillRowLink from "app/frontend/components/bill/BillRowLink";
import { Badge } from "app/frontend/components/ui/badge";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ILegislatorBillOfTheMonthVote } from "app/frontend/types/legislators";

interface IProps {
    votes: ILegislatorBillOfTheMonthVote[];
    isSignedIn: boolean;
}

type TVote = NonNullable<ILegislatorBillOfTheMonthVote["legislator_vote"]>;
type TTone = "success" | "danger" | "neutral";

const VOTE_LABEL: Record<TVote, string> = { FOR: "For", AGAINST: "Against", ABSTAIN: "Abstain" };
const VOTE_TONE: Record<TVote, TTone> = { FOR: "success", AGAINST: "danger", ABSTAIN: "neutral" };

const HEADING_ID = "legislator-botm-record-heading";

const formatReleaseMonth = (iso: string): string =>
    new Date(iso).toLocaleDateString("en-US", { month: "short", year: "numeric", timeZone: "UTC" });

// @lat: [[legislator-botm-record#Bill of the Month voting record on the legislator page]]
const LegislatorBillOfTheMonthRecord: React.FC<IProps> = ({ votes, isSignedIn }) => (
    <section
        aria-labelledby={HEADING_ID}
        data-testid="legislator-botm-record"
        className="space-y-3 rounded-2xl border-neo border-border-strong bg-card/95 p-5 shadow-neo"
    >
        <h2 id={HEADING_ID} className="text-xs font-black uppercase tracking-[0.18em] text-muted-foreground">
            {PARITY_COPY.legislators.votingRecordHeading}
        </h2>
        {votes.length === 0 ? (
            <p className="text-sm text-muted-foreground">{PARITY_COPY.legislators.votingRecordEmpty}</p>
        ) : (
            <ul className="space-y-3">
                {votes.map((entry) => (
                    <li
                        key={entry.bill_id}
                        data-testid={`botm-record-row-${entry.bill_id}`}
                        className="space-y-2 rounded-xl border-neo border-border-strong bg-surface-2 px-4 py-3"
                    >
                        <p className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                            <time dateTime={entry.scheduled_release_date_utc}>
                                {formatReleaseMonth(entry.scheduled_release_date_utc)}
                            </time>
                            {` · ${entry.external_id.toUpperCase()}`}
                        </p>
                        <BillRowLink
                            billId={entry.bill_id}
                            className="block text-sm font-semibold text-foreground underline-offset-2 hover:underline"
                        >
                            {entry.title}
                        </BillRowLink>
                        <dl className="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs">
                            <div className="flex items-center gap-2">
                                <dt className="text-muted-foreground">{PARITY_COPY.legislators.legislatorVoteLabel}</dt>
                                <dd>
                                    <Badge
                                        variant="stamp"
                                        tone={entry.legislator_vote ? VOTE_TONE[entry.legislator_vote] : "neutral"}
                                        data-testid={`botm-legislator-vote-${entry.bill_id}`}
                                    >
                                        {entry.legislator_vote
                                            ? VOTE_LABEL[entry.legislator_vote]
                                            : PARITY_COPY.legislators.noRecordedVote}
                                    </Badge>
                                </dd>
                            </div>
                            {isSignedIn && (
                                <div className="flex items-center gap-2">
                                    <dt className="text-muted-foreground">{PARITY_COPY.legislators.yourVoteLabel}</dt>
                                    <dd className="flex items-center gap-2">
                                        <Badge
                                            variant="stamp"
                                            tone={entry.user_vote ? VOTE_TONE[entry.user_vote] : "neutral"}
                                            data-testid={`botm-user-vote-${entry.bill_id}`}
                                        >
                                            {entry.user_vote
                                                ? VOTE_LABEL[entry.user_vote]
                                                : PARITY_COPY.legislators.notVotedYet}
                                        </Badge>
                                        {entry.alignment && (
                                            <Badge
                                                variant="solid"
                                                tone={entry.alignment === "agreed" ? "success" : "danger"}
                                                data-testid={`botm-alignment-${entry.bill_id}`}
                                            >
                                                {entry.alignment === "agreed"
                                                    ? PARITY_COPY.legislators.agreedBadge
                                                    : PARITY_COPY.legislators.disagreedBadge}
                                            </Badge>
                                        )}
                                    </dd>
                                </div>
                            )}
                        </dl>
                    </li>
                ))}
            </ul>
        )}
    </section>
);

export default LegislatorBillOfTheMonthRecord;
