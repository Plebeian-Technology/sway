import { useState } from "react";
import { Button } from "app/frontend/components/ui/button";

// @lat: [[campaign-position-cards#How claimed-affiliation evidence is structured and guarded]]
export interface IClaimedAffiliationEvidence {
    phrase: string | null;
    role: string | null;
    sender: string | null;
}

interface IProps {
    evidence: IClaimedAffiliationEvidence;
}

// @lat: [[campaign-position-cards#How claimed-affiliation evidence is structured and guarded]]
const PHRASE_DISCLOSURE_THRESHOLD_CHARS = 160;

// @lat: [[campaign-position-cards#How claimed-affiliation evidence is structured and guarded]]
const ClaimedAffiliationEvidence: React.FC<IProps> = ({ evidence }) => {
    const { phrase, role, sender } = evidence;
    const [phraseExpanded, setPhraseExpanded] = useState<boolean>(false);

    if (!phrase && !role && !sender) return null;

    const phraseNeedsDisclosure = !!phrase && phrase.length > PHRASE_DISCLOSURE_THRESHOLD_CHARS;
    // @lat: [[campaign-position-cards#How claimed-affiliation evidence is structured and guarded]]
    const phraseClassName = phraseExpanded || !phraseNeedsDisclosure ? "text-sm" : "text-sm line-clamp-2";

    return (
        <dl className="flex flex-col gap-3" data-testid="claimed-affiliation-evidence">
            {phrase && (
                <div className="flex flex-col gap-1">
                    <dt className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">Phrase</dt>
                    <dd className={phraseClassName}>{phrase}</dd>
                    {phraseNeedsDisclosure && (
                        <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            className="w-fit min-h-[44px] text-xs underline sm:min-h-0"
                            onClick={() => setPhraseExpanded((prev) => !prev)}
                            data-testid="btn-claimed-affiliation-phrase-disclosure"
                        >
                            {phraseExpanded ? "Show less" : "Show the whole phrase"}
                        </Button>
                    )}
                </div>
            )}
            {role && (
                <div className="flex flex-col gap-1">
                    <dt className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                        Role claimed
                    </dt>
                    <dd className="text-sm">{role}</dd>
                </div>
            )}
            {sender && (
                <div className="flex flex-col gap-1">
                    <dt className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">Sender</dt>
                    <dd className="text-sm">{sender}</dd>
                </div>
            )}
        </dl>
    );
};

export default ClaimedAffiliationEvidence;
