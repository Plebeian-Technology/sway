import { usePage } from "@inertiajs/react";
import { sway } from "sway";

import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { formatDeployedAt, releaseLabel } from "app/frontend/sway_utils/release";
import { useUser } from "app/frontend/hooks/users/useUser";
import { formatPhone } from "app/frontend/sway_utils/phone";

// @lat: [[system-shape#Deployment#The logo tooltip includes the running build]]
interface IProps {
    children?: React.ReactNode;
}

const ReleaseInfo: React.FC<IProps> = ({ children }) => {
    const release = usePage<sway.IPageProps>().props.release;
    const user = useUser();

    return (
        <TooltipProvider delayDuration={200}>
            <Tooltip>
                <TooltipTrigger asChild>{children}</TooltipTrigger>
                <TooltipContent side="bottom" align="start" className="max-w-none">
                    <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
                        {!import.meta.env.PROD && user?.phone && (
                            <>
                                <dt className="font-semibold text-muted-foreground">User</dt>
                                <dd className="font-black text-foreground">{formatPhone(user.phone)}</dd>
                            </>
                        )}

                        <dt className="font-semibold text-muted-foreground">Build</dt>
                        <dd className="font-black text-foreground">{releaseLabel(release)}</dd>

                        <dt className="font-semibold text-muted-foreground">Deployed</dt>
                        <dd className="text-foreground">{formatDeployedAt(release?.deployed_at)}</dd>

                        <dt className="font-semibold text-muted-foreground">Commit</dt>
                        <dd className="font-mono text-foreground">{release?.short_sha ?? "unknown"}</dd>

                        {/* @lat: [[system-shape#Deployment#The logo tooltip includes the running build]] */}
                        <dt className="font-semibold text-muted-foreground">Built from</dt>
                        {release?.built_from_committed_tree === false ? (
                            <dd className="text-destructive">
                                that commit plus uncommitted changes ({release.uncommitted_digest})
                            </dd>
                        ) : release?.built_from_committed_tree === true ? (
                            <dd className="text-foreground">exactly that commit</dd>
                        ) : (
                            <dd className="text-muted-foreground">not recorded</dd>
                        )}

                        {release?.previous_short_sha ? (
                            <>
                                <dt className="font-semibold text-muted-foreground">Previous</dt>
                                <dd className="font-mono text-foreground">{release.previous_short_sha}</dd>
                            </>
                        ) : null}
                    </dl>
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
};

export default ReleaseInfo;
