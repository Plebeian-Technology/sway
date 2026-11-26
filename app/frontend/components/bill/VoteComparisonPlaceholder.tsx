import React from "react";
import { usePage, Link } from "@inertiajs/react";
import toast from "react-hot-toast";
import { PARITY_COPY } from "../../sway_constants/parityCopy";

interface IProps {
    votersNeeded?: number;
}

const VoteComparisonPlaceholder: React.FC<IProps> = ({ votersNeeded }) => {
    const { user } = usePage<any>().props;

    const copyInviteLink = async () => {
        if (user?.invite_url) {
            await navigator.clipboard.writeText(user.invite_url);
            toast(PARITY_COPY.bill.shareCopied);
        }
    };

    if (votersNeeded === undefined || votersNeeded === null) {
        return (
            <div className="text-muted text-sm mt-2">
                {PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotesYet}
            </div>
        );
    }

    return (
        <div className="flex flex-col gap-2 mt-2">
            <p className="text-sm text-muted">{PARITY_COPY.bill.voteComparisonPlaceholder.message(votersNeeded)}</p>
            {user ? (
                user.invite_url ? (
                    <>
                        <p className="text-sm text-muted">{PARITY_COPY.bill.voteComparisonPlaceholder.invitePrompt}</p>
                        <button onClick={copyInviteLink} className="text-sm font-semibold text-primary underline">
                            {PARITY_COPY.bill.voteComparisonPlaceholder.inviteButton}
                        </button>
                    </>
                ) : null
            ) : (
                <>
                    <p className="text-sm text-muted">{PARITY_COPY.bill.voteComparisonPlaceholder.invitePrompt}</p>
                    <Link href="/sign_up" className="text-sm font-semibold text-primary underline">
                        {PARITY_COPY.bill.voteComparisonPlaceholder.inviteButton}
                    </Link>
                </>
            )}
        </div>
    );
};

export default VoteComparisonPlaceholder;
