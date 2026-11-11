import { router } from "@inertiajs/react";
import { useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { ITestimonyCoverage } from "app/frontend/components/admin/creator/llm-summary/types";
import { formatDateTime } from "app/frontend/sway_utils/datetimes";

interface IProps {
    billId: number;
    coverage: ITestimonyCoverage;
    runInFlight: boolean;
}

// @lat: [[campaign-letter-disclosure#Testimony coverage states and acknowledgement gate]]
const TestimonyAcknowledgeButton: React.FC<IProps> = ({ billId, coverage, runInFlight }) => {
    const [submitting, setSubmitting] = useState<boolean>(false);

    if (coverage.acknowledged) {
        return (
            <div className="flex flex-col gap-1" data-testid="testimony-acknowledged-stamp">
                <Badge variant="stamp" tone="neutral">
                    ACKNOWLEDGED
                </Badge>
                <p className="text-sm text-muted-foreground">
                    Acknowledged by {coverage.acknowledged_by_email}
                    {coverage.acknowledged_at && ` on ${formatDateTime(coverage.acknowledged_at)}`}.
                </p>
            </div>
        );
    }

    const handleClick = () => {
        setSubmitting(true);
        router.post(
            `/bills/${billId}/testimony_coverage_acknowledgement`,
            { digest: coverage.digest },
            {
                preserveScroll: true,
                onError: (errors) => notifyServerRefusal(errors, "testimony_coverage", "Acknowledgement failed."),
                onFinish: () => setSubmitting(false),
            },
        );
    };

    return (
        <div className="flex items-center gap-1.5">
            <Button
                type="button"
                size="sm"
                variant="default"
                onClick={handleClick}
                disabled={submitting || runInFlight}
            >
                Acknowledge the missing testimony
            </Button>
            <FeatureInfo note="summary.coverageAcknowledgement" />
        </div>
    );
};

export default TestimonyAcknowledgeButton;
