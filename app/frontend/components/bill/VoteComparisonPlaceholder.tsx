import { Link } from "@inertiajs/react";
import copy from "copy-to-clipboard";

import { Button } from "app/frontend/components/ui/button";
import { useUser } from "app/frontend/hooks/users/useUser";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { notify } from "app/frontend/sway_utils";

interface IProps {
    votersNeeded?: number | null;
    className?: string;
}

// @lat: [[voter-privacy-threshold#The placeholder shown in place of a hidden comparison]]
const VoteComparisonPlaceholder: React.FC<IProps> = ({ votersNeeded, className }) => {
    const user = useUser();
    const inviteUrl = user?.invite_url;

    if (votersNeeded === undefined || votersNeeded === null) {
        return (
            <p className={className ?? "text-sm text-muted-foreground"}>
                {PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotes}
            </p>
        );
    }

    const copyInviteLink = async (url: string) => {
        if (await copy(url)) {
            notify({ level: "info", title: PARITY_COPY.bill.voteComparisonPlaceholder.inviteLinkCopied });
        }
    };

    return (
        <div className={className ?? "space-y-3 text-sm text-muted-foreground"}>
            <p>{PARITY_COPY.bill.voteComparisonPlaceholder.votersNeeded(votersNeeded)}</p>
            <p>{PARITY_COPY.bill.voteComparisonPlaceholder.invitePrompt}</p>
            {inviteUrl && (
                <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => copyInviteLink(inviteUrl).catch(() => {})}
                >
                    {PARITY_COPY.bill.voteComparisonPlaceholder.copyInviteLink}
                </Button>
            )}
            {!user && (
                <Button asChild variant="outline" size="sm">
                    <Link href={ROUTES.signin}>{PARITY_COPY.bill.voteComparisonPlaceholder.signUp}</Link>
                </Button>
            )}
        </div>
    );
};

export default VoteComparisonPlaceholder;
