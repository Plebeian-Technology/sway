import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { TESTIMONY_COVERAGE_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/testimonyCoverageNoticeId";
import { ITestimonyCoverage } from "app/frontend/components/admin/creator/llm-summary/types";
import { countNoun } from "app/frontend/sway_utils/countNoun";
import TestimonyAcknowledgeButton from "app/frontend/components/admin/creator/testimony-report/TestimonyAcknowledgeButton";

interface IProps {
    billId: number;
    coverage: ITestimonyCoverage;
    runInFlight: boolean;
}

interface INoticeContent {
    title: string;
    body: string;
    variant: "info" | "warning";
}

// @lat: [[campaign-letter-disclosure#Testimony coverage states and acknowledgement gate]]
const neverRunContent = (coverage: ITestimonyCoverage): INoticeContent => ({
    title: "This testimony was not cleaned",
    body:
        `The clean-testimony stage has not run on this bill. The model read the first ` +
        `${countNoun(coverage.reached_chars ?? 0, "character", "characters")} of ${(coverage.total_chars ?? 0).toLocaleString()}.`,
    variant: "warning",
});

// @lat: [[campaign-letter-disclosure#Testimony coverage states and acknowledgement gate]]
const failedContent = (coverage: ITestimonyCoverage): INoticeContent => {
    if (
        coverage.total_letters === null ||
        coverage.total_letters === undefined ||
        coverage.left_out_letters === null ||
        coverage.left_out_letters === undefined
    ) {
        return {
            title: "The clean-testimony stage failed",
            body:
                `The model read the raw testimony instead. It read the first ` +
                `${countNoun(coverage.reached_chars ?? 0, "character", "characters")} of ${(coverage.total_chars ?? 0).toLocaleString()}.`,
            variant: "warning",
        };
    }

    return {
        title: "The clean-testimony stage failed",
        body:
            `The model read the raw testimony instead. ${(coverage.left_out_letters ?? 0).toLocaleString()} of ` +
            `${countNoun(coverage.total_letters ?? 0, "letter", "letters")} did not reach the model.`,
        variant: "warning",
    };
};

// @lat: [[campaign-letter-disclosure#Testimony coverage states and acknowledgement gate]]
const cleanedContent = (coverage: ITestimonyCoverage): INoticeContent => {
    const totalLetters = coverage.total_letters ?? 0;
    const leftOutLetters = coverage.left_out_letters ?? 0;

    if (leftOutLetters === 0 && (coverage.left_out_chars ?? 0) === 0) {
        return {
            title: "Testimony coverage",
            body: `All ${countNoun(totalLetters, "letter", "letters")} reached the model. Repeated text was removed first.`,
            variant: "info",
        };
    }

    // @lat: [[campaign-letter-disclosure#Testimony coverage states and acknowledgement gate]]
    if (leftOutLetters === 0) {
        return {
            title: "Some testimony did not reach the model",
            body:
                `${countNoun(totalLetters, "letter", "letters")} reached the model, but not in full. ` +
                `The prompt reached its size limit. Approval is blocked until you acknowledge this.`,
            variant: "warning",
        };
    }

    return {
        title: "Some testimony did not reach the model",
        body:
            `${leftOutLetters.toLocaleString()} of ${countNoun(totalLetters, "letter", "letters")} did not reach the model. ` +
            `The prompt reached its size limit. Approval is blocked until you acknowledge this.`,
        variant: "warning",
    };
};

// @lat: [[campaign-letter-disclosure#Testimony coverage states and acknowledgement gate]]
const staleContent = (coverage: ITestimonyCoverage): INoticeContent => ({
    title: "This testimony needs to be cleaned again",
    body:
        `Newer hearing testimony arrived after this bill was last cleaned, so the model read the raw testimony instead. ` +
        `It read the first ${countNoun(coverage.reached_chars ?? 0, "character", "characters")} of ${(coverage.total_chars ?? 0).toLocaleString()}. ` +
        `Re-run the clean-testimony stage.`,
    variant: "warning",
});

const noticeContent = (coverage: ITestimonyCoverage): INoticeContent => {
    switch (coverage.state) {
        case "running":
            return {
                title: "The clean-testimony stage is running",
                body: "These numbers come from the last run.",
                variant: "info",
            };
        case "never_run":
            return neverRunContent(coverage);
        case "failed":
            return failedContent(coverage);
        case "stale":
            return staleContent(coverage);
        default:
            return cleanedContent(coverage);
    }
};

// @lat: [[campaign-letter-disclosure#Campaign letter disclosure#How much testimony reached the model is stated, not implied]]
const LlmSummaryTestimonyCoverageNotice: React.FC<IProps> = ({ billId, coverage, runInFlight }) => {
    if (coverage.state === "no_testimony") return null;

    const { title, body, variant } = noticeContent(coverage);

    return (
        <Alert variant={variant} id={TESTIMONY_COVERAGE_NOTICE_ID} data-testid="llm-testimony-coverage-notice">
            <div className="col-start-2 flex min-w-0 items-center gap-1.5">
                <AlertTitle>{title}</AlertTitle>
                <FeatureInfo note="summary.testimonyCoverage" />
            </div>
            <AlertDescription>
                <p className="text-sm tabular-nums lining-nums">{body}</p>
                {/* @lat: [[campaign-letter-disclosure#Testimony coverage states and acknowledgement gate]] */}
                {coverage.coverage_gap && (
                    <div className="pt-2">
                        <TestimonyAcknowledgeButton billId={billId} coverage={coverage} runInFlight={runInFlight} />
                    </div>
                )}
            </AlertDescription>
        </Alert>
    );
};

export default LlmSummaryTestimonyCoverageNotice;
