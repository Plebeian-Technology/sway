import TestimonyRecordBar from "app/frontend/components/admin/creator/testimony-report/TestimonyRecordBar";
import TestimonyCampaignTable from "app/frontend/components/admin/creator/testimony-report/TestimonyCampaignTable";
import TestimonyPasteNotice from "app/frontend/components/admin/creator/testimony-report/TestimonyPasteNotice";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { ITestimonyCampaignDraft, ITestimonyCoverage } from "app/frontend/components/admin/creator/llm-summary/types";
import { countNoun } from "app/frontend/sway_utils/countNoun";

interface IProps {
    coverage: ITestimonyCoverage | null | undefined;
    campaignDrafts: ITestimonyCampaignDraft[];
}

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const staleHeader = (coverage: ITestimonyCoverage): React.ReactNode => {
    if (coverage.state === "running") {
        return (
            <p className="text-xs text-muted-foreground">
                The clean-testimony stage is running. These numbers are from the last run.
            </p>
        );
    }
    if (coverage.state === "failed") {
        return (
            <p className="text-xs text-warning">
                The clean-testimony stage failed. These numbers are from the last successful run.
            </p>
        );
    }
    if (coverage.state === "stale") {
        return (
            <p className="text-xs text-warning">
                Newer hearing testimony arrived after this bill was last cleaned. These numbers are from the raw
                testimony — re-run the stage.
            </p>
        );
    }
    return null;
};

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const individualsBlock = (coverage: ITestimonyCoverage): React.ReactNode => {
    if (coverage.individual_letter_count === null) return null;

    if (coverage.individual_letter_count === 0) {
        return <p className="text-sm">No letters came from people speaking for themselves.</p>;
    }

    return (
        <p className="text-sm tabular-nums lining-nums">
            {`${countNoun(coverage.individual_letter_count, "letter", "letters")} came from people speaking for themselves. The model read them. They cannot become an organization position.`}
        </p>
    );
};

const modelFallbackBlock = (coverage: ITestimonyCoverage): React.ReactNode => {
    if (!coverage.model_fallback_letter_count) return null;

    return (
        <p className="text-sm tabular-nums lining-nums text-warning">
            {`${countNoun(coverage.model_fallback_letter_count, "letter", "letters")} took the safe kind because the model was not asked or did not answer. A letter reading as an organization's own voice becomes a person speaking for themselves, and approving that organization is then refused.`}
        </p>
    );
};

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const TestimonyReport: React.FC<IProps> = ({ coverage, campaignDrafts }) => {
    if (!coverage || coverage.state === "no_testimony") return null;

    const individuals = individualsBlock(coverage);
    const modelFallbacks = modelFallbackBlock(coverage);

    return (
        <div className="flex flex-col gap-6" data-testid="testimony-report">
            <div className="flex flex-col gap-3">
                <div className="flex items-center gap-1.5">
                    <h4 className="text-xs font-semibold uppercase tracking-widest">Testimony report</h4>
                    <FeatureInfo note="pipeline.testimonyReport" />
                </div>
                <div className="border-b-neo border-border-soft" />
                {staleHeader(coverage)}
            </div>

            <div className="flex flex-col gap-3">
                <div className="flex items-center gap-1.5">
                    <h5 className="text-xs font-semibold uppercase tracking-widest">What reached the model</h5>
                    <FeatureInfo note="pipeline.recordBar" />
                </div>
                <TestimonyRecordBar
                    reachedChars={coverage.reached_chars}
                    removedChars={coverage.removed_chars}
                    repairAddedChars={coverage.repair_added_chars}
                    leftOutChars={coverage.left_out_chars}
                    totalChars={coverage.total_chars}
                />
            </div>

            <div className="flex flex-col gap-3">
                <div className="flex items-center gap-1.5">
                    <h5 className="text-xs font-semibold uppercase tracking-widest">Campaigns</h5>
                    <FeatureInfo note="pipeline.campaignsTable" />
                </div>
                <TestimonyCampaignTable rows={campaignDrafts} />
            </div>

            {individuals && (
                <div className="flex flex-col gap-3">
                    <h5 className="text-xs font-semibold uppercase tracking-widest">People speaking for themselves</h5>
                    {individuals}
                </div>
            )}

            {modelFallbacks && (
                <div className="flex flex-col gap-3">
                    <h5 className="text-xs font-semibold uppercase tracking-widest">Letters the model never judged</h5>
                    {modelFallbacks}
                </div>
            )}

            {coverage.paste_present && (
                <div className="flex flex-col gap-3">
                    <div className="flex items-center gap-1.5">
                        <h5 className="text-xs font-semibold uppercase tracking-widest">Your pasted testimony</h5>
                        <FeatureInfo note="pipeline.pastedTestimony" />
                    </div>
                    <TestimonyPasteNotice
                        pasteChars={coverage.paste_chars}
                        pasteShareOfLimit={coverage.paste_share_of_limit}
                        displacedLetterCount={coverage.displaced_letter_count}
                    />
                </div>
            )}
        </div>
    );
};

export default TestimonyReport;
