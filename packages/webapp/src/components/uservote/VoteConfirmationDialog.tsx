/** @format */

import { createStyles, makeStyles, Typography } from "@material-ui/core";
import React from "react";
import { sway } from "sway";
import ConfirmationDialog from "../dialogs/ConfirmationDialog";

interface IProps {
    open: boolean;
    handleClose: (event: boolean) => void;
    support: "for" | "against";
    bill: sway.IBill;
    isSubmitting: boolean;
}

const useStyles = makeStyles(() => {
    return createStyles({
        textContainer: {
            margin: "20px auto",
            fontWeight: "bold",
            textAlign: "center",
            lineHeight: 1,
        },
        text: { fontWeight: 700 },
        warning: {
            fontSize: "1.2em",
            fontWeight: 900,
        },
    });
});

// div.confirmation-dialog.vote-confirmation-dialog {
//     button {
//         span {
//             font-weight: bold;
//         }
//         span:first-child {
//             border-bottom: 2px solid transparent;
//         }
//         border: none;
//     }
//     button.confirmation-dialog-button-falsey:hover {
//         background-color: transparent;
//         span:first-child {
//             border-bottom: 2px solid $tertiary;
//         }
//     }
//     button.confirmation-dialog-button-truthy:hover {
//         background-color: transparent;
//         span:first-child {
//             border-bottom: 2px solid $primary;
//         }
//     }
// }

const VoteConfirmationDialog: React.FC<IProps> = (props) => {
    const classes = useStyles();
    const { open, handleClose, support, bill, isSubmitting } = props;

    const text = bill.votedate ? (
        "Sway votes, like those cast by legislators, are final."
    ) : (
        <Typography className={classes.textContainer}>
            <Typography variant="body1" className={classes.text}>
                <span className={classes.warning}>WARNING:</span> Legislators
                have not yet voted on a final version of this bill.
            </Typography>
            <br />
            <Typography variant="body1" className={classes.text}>
                It may be amended before a final vote.
            </Typography>
        </Typography>
    );

    return (
        <ConfirmationDialog
            open={open}
            handleClose={handleClose}
            title={`Are you sure you want to vote "${support}" on bill ${bill.firestoreId}?`}
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
