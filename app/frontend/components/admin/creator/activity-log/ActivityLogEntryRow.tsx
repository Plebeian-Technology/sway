import { memo } from "react";
import type { ActivityLogEntry } from "app/frontend/types/activityLog";
import { notify } from "app/frontend/sway_utils";
import { relativeTime } from "app/frontend/sway_utils/datetimes";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { SEVERITY_TONE } from "app/frontend/components/admin/creator/activity-log/constants";

interface IProps {
    entry: ActivityLogEntry;
}

// @lat: [[activity-log-stream#Memoized rows and default-omitting filter URLs]]
const ActivityLogEntryRow: React.FC<IProps> = ({ entry }) => {
    return (
        <li
            id={`activity-log-entry-${entry.id}`}
            className="flex flex-col gap-1 border-b border-border-soft py-3 hover:bg-secondary/40"
        >
            <div className="flex flex-wrap items-center gap-2">
                <Badge variant="stamp" tone={SEVERITY_TONE[entry.severity]} aria-label={`Severity: ${entry.severity}`}>
                    {entry.severity}
                </Badge>
                <span className="text-sm font-semibold">{entry.title}</span>
                {entry.subject_label && <span className="text-xs text-muted-foreground">{entry.subject_label}</span>}
                <span className="text-xs text-muted-foreground">
                    {entry.actor_user_id ? `User #${entry.actor_user_id}` : "System"}
                </span>
                <span className="ml-auto">
                    <time
                        dateTime={entry.created_at}
                        className="text-xs tabular-nums lining-nums text-muted-foreground"
                        title={entry.created_at}
                    >
                        {relativeTime(entry.created_at)}
                    </time>
                </span>
            </div>
            {entry.message && <p className="text-sm text-muted-foreground">{entry.message}</p>}
            <details aria-label={`Activity log entry details for ${entry.title}`}>
                <summary className="flex min-h-[44px] cursor-pointer items-center text-xs text-muted-foreground">
                    Details
                </summary>
                <pre className="mt-1 max-w-full overflow-x-auto text-xs">{JSON.stringify(entry.payload, null, 2)}</pre>
                {entry.inspect_query && (
                    <div className="mt-2 flex items-start gap-2">
                        <code className="flex-1 overflow-x-auto rounded bg-muted px-2 py-1 text-xs">
                            {entry.inspect_query}
                        </code>
                        <Button
                            variant="ghost"
                            size="sm"
                            className="min-h-[44px] min-w-[44px] shrink-0 text-xs"
                            onClick={() => {
                                navigator.clipboard
                                    .writeText(entry.inspect_query)
                                    .then(() =>
                                        notify({
                                            level: "info",
                                            title: "Copied AR query",
                                            message: "Paste into rails console.",
                                            duration: 2500,
                                        }),
                                    )
                                    .catch(() =>
                                        notify({
                                            level: "error",
                                            title: "Copy failed",
                                            message: "Clipboard write rejected — select and copy manually.",
                                        }),
                                    );
                            }}
                        >
                            Copy
                        </Button>
                    </div>
                )}
            </details>
        </li>
    );
};

export default memo(ActivityLogEntryRow);
