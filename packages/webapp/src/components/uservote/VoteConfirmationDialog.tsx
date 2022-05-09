/** @format */

import { sway } from "sway";
import ConfirmationDialog from "../dialogs/ConfirmationDialog";

interface IProps {
    open: boolean;
    handleClose: (event: boolean) => void;
    support: sway.TSupport;
    bill: sway.IBill;
    isSubmitting: boolean;
}

const VoteConfirmationDialog: React.FC<IProps> = (props) => {
    const { open, handleClose, support, bill, isSubmitting } = props;

    const text = (
        <div>
            <p>
                Are you sure you want to vote <span className="bold">"{support}"</span> on bill{" "}
                {bill.firestoreId} - {bill.title}?
            </p>
            <p>Like votes cast by legislators, all votes through Sway are final.</p>
            {bill.votedate ? (
                <p>Legislators have already voted on this bill.</p>
            ) : (
                <>
                    <p>
                        <span className="bold">WARNING:</span> Legislators have not yet voted on a
                        final version of this bill.
                    </p>
                    <p>It may be amended before a final vote.</p>
                </>
            )}
        </div>
    );

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
