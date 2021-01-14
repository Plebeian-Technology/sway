/** @format */

import React from "react";
import ConfirmationDialog from "../dialogs/ConfirmationDialog";

interface IProps {
    open: boolean;
    handleClose: (event: boolean) => void;
    support: string;
    billFirestoreId: string;
    isSubmitting: boolean;
}

const VoteConfirmationDialog: React.FC<IProps> = (props) => {
    const { open, handleClose, support, billFirestoreId, isSubmitting } = props;

    return (
            <ConfirmationDialog
                open={open}
                handleClose={handleClose}
                className="vote-confirmation-dialog"
                title={`Are you sure you want to vote "${support}" on bill ${billFirestoreId}?`}
                text={
                    "Sway votes, like those cast by legislators, are final."
                }
                isLoading={isSubmitting}
                options={{
                    truthy: "Continue",
                    falsey: "Cancel",
                }}
            />
    );
};

export default VoteConfirmationDialog;
