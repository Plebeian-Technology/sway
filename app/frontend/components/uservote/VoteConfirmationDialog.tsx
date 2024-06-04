/** @format */

import { sway } from "sway";
import ConfirmationDialog from "../dialogs/ConfirmationDialog";
import { useMemo } from "react";

interface IProps {
    open: boolean;
    handleClose: (event: boolean) => void;
    support: sway.TUserSupport;
    bill: sway.IBill;
    isSubmitting: boolean;
}

const VoteConfirmationDialog: React.FC<IProps> = (props) => {
    const { open, handleClose, support, bill, isSubmitting } = props;

    const text = useMemo(() => (
        <div>
            <div className="my-2">
                Are you sure you want to vote <span className="bold">"{support}"</span> on bill{" "}
                {bill.externalId} - {bill.title}?
            </div>
            <div className="my-2">
                Like votes cast by legislators, all votes through Sway are final.
            </div>
            {bill.voteDateTimeUtc ? (
                <div className="my-2">Legislators have already voted on this bill.</div>
            ) : (
                <>
                    <div className="my-2">
                        <span className="bold">WARNING:</span> Legislators have not yet voted on a
                        final version of this bill.
                    </div>
                    <div className="my-2">It may be amended before a final vote.</div>
                </>
            )}
        </div>
    ), [bill.externalId, bill.title, bill.voteDateTimeUtc, support]);

    return (
        <ConfirmationDialog
            open={open}
            handleClose={handleClose}
            title="Confirm Vote"
            text={text}
            isLoading={isSubmitting}
            options={{
                truthy: "Continue",
                falsey: "Cancel",
            }}
        />
    );
};

export default VoteConfirmationDialog;
