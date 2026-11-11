import { router } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import Pagination from "app/frontend/components/Pagination";
import { ITestimonyCampaignLetter } from "app/frontend/components/admin/creator/llm-summary/types";
import { usePagination } from "app/frontend/hooks/usePagination";
import { countNoun } from "app/frontend/sway_utils/countNoun";

interface IProps {
    // @lat: [[campaign-letter-disclosure#Why the letter text is a prop of its own]]
    letters: ITestimonyCampaignLetter[] | undefined;
    letterCount: number;
}

const senderLabel = (letter: ITestimonyCampaignLetter): string =>
    letter.sender_address || letter.sender_domain || "Unknown sender";

// @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why the letters page one at a time]]
const LETTERS_PER_PAGE = 1;

// @lat: [[campaign-letter-disclosure#Why the letter list is not a CollapsiblePanel]]
const CampaignLetterList: React.FC<IProps> = ({ letters, letterCount }) => {
    const [expanded, setExpanded] = useState<boolean>(false);
    const [requested, setRequested] = useState<boolean>(false);
    const [failed, setFailed] = useState<boolean>(false);
    const [settled, setSettled] = useState<boolean>(false);
    const pager = usePagination(letters ?? [], LETTERS_PER_PAGE);

    // @lat: [[campaign-letter-disclosure#Why the list asks for its own letters]]
    const requestLetters = useCallback(() => {
        setRequested(true);
        setFailed(false);
        setSettled(false);
        router.reload({
            only: ["testimony_campaign_letters"],
            onError: () => setFailed(true),
            onFinish: () => setSettled(true),
        });
    }, []);

    const handleToggle = useCallback(() => {
        const opening = !expanded;
        setExpanded(opening);
        if (!opening) return;
        if (letters !== undefined) return;
        if (requested) return;
        requestLetters();
    }, [expanded, letters, requested, requestLetters]);

    if (letterCount === 0) return null;

    return (
        <div className="flex flex-col gap-2" data-testid="campaign-letter-list">
            <div className="flex items-center gap-1.5">
                <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="w-fit text-xs underline"
                    onClick={handleToggle}
                    data-testid="btn-campaign-letters-disclosure"
                >
                    {expanded ? "Hide letters" : `Show ${countNoun(letterCount, "letter", "letters")}`}
                </Button>
                <FeatureInfo note="summary.campaignLetters" />
            </div>
            {expanded && letters === undefined && !failed && !settled && (
                <p className="text-sm text-muted-foreground" data-testid="campaign-letters-loading">
                    Loading letters…
                </p>
            )}
            {expanded && letters === undefined && failed && (
                <div className="flex flex-col items-start gap-2" data-testid="campaign-letters-error">
                    <p className="text-sm text-muted-foreground">The letters could not be loaded.</p>
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={requestLetters}
                        data-testid="btn-campaign-letters-retry"
                    >
                        Try again
                    </Button>
                </div>
            )}
            {expanded && !failed && (letters?.length === 0 || (letters === undefined && settled)) && (
                <p className="text-sm text-muted-foreground" data-testid="campaign-letters-empty">
                    No letter text could be produced for this campaign.
                </p>
            )}
            {expanded && letters !== undefined && letters.length > 0 && (
                <Pagination
                    page={pager.page}
                    pageCount={pager.pageCount}
                    onPageChange={pager.goToPage}
                    className="justify-center"
                />
            )}
            {expanded && letters !== undefined && letters.length > 0 && (
                <ul className="flex flex-col gap-3" data-testid="campaign-letter-items">
                    {pager.pageItems.map((letter) => (
                        <li
                            key={letter.position}
                            className="flex flex-col gap-1 rounded-lg border-neo border-border-strong bg-surface-2 p-3"
                        >
                            <span className="flex flex-wrap items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                                <span
                                    className="tabular-nums lining-nums"
                                    data-testid={`campaign-letter-id-${letter.position}`}
                                >
                                    Letter #{letter.position}
                                </span>
                                <span>{senderLabel(letter)}</span>
                                {letter.repeat && (
                                    <Badge
                                        variant="stamp"
                                        tone="neutral"
                                        data-testid={`campaign-letter-repeat-${letter.position}`}
                                    >
                                        DUPLICATE
                                    </Badge>
                                )}
                            </span>
                            <p className="whitespace-pre-wrap text-sm">{letter.text}</p>
                        </li>
                    ))}
                </ul>
            )}
            {expanded && letters !== undefined && letters.length > 0 && (
                <Pagination
                    page={pager.page}
                    pageCount={pager.pageCount}
                    onPageChange={pager.goToPage}
                    className="justify-center"
                />
            )}
        </div>
    );
};

export default CampaignLetterList;
