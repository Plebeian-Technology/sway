// @lat: [[pipeline-activity-log-error-banner-fallback#Why each delivery path has its own rescue]]

import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";

interface IProps {
    activityLogError: { entry_id: number; error_class: string };
}

const ActivityLogErrorBanner: React.FC<IProps> = ({ activityLogError }) => {
    return (
        <Alert variant="destructive" data-testid="activity-log-error-banner">
            <AlertTitle>Activity-log delivery failed</AlertTitle>
            <AlertDescription>
                Entry{" "}
                <a
                    href={(() => {
                        // @lat: [[pipeline-activity-log-error-banner-fallback#The banner's link resolves against the current path]]
                        const params = new URLSearchParams(typeof window === "undefined" ? "" : window.location.search);
                        params.set("highlight", String(activityLogError.entry_id));
                        return `?${params.toString()}`;
                    })()}
                    className="rounded px-1 py-0.5 underline tabular-nums lining-nums"
                >
                    #{activityLogError.entry_id}
                </a>{" "}
                was written but the toast notification could not be delivered (
                <span className="font-mono text-xs">{activityLogError.error_class}</span>). Click the entry id to jump
                to the row.
            </AlertDescription>
        </Alert>
    );
};

export default ActivityLogErrorBanner;
