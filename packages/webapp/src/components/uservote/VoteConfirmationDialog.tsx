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

const VoteConfirmationDialog: React.FC<IProps> = (props) => {
    const classes = useStyles();
    const { open, handleClose, support, bill, isSubmitting } = props;

    const text = bill.votedate ? (
        "Legislators have already voted on this bill."
    ) : (
        <span className={classes.textContainer}>
            <Typography component={"span"} variant="body1" className={classes.text}>
                <span className={classes.warning}>WARNING:</span> Legislators
                have not yet voted on a final version of this bill.
            </Typography>
            <br />
            <Typography component={"span"} variant="body1" className={classes.text}>
                It may be amended before a final vote.
            </Typography>
        </span>
    );

    return (
        <ConfirmationDialog
            open={open}
            handleClose={handleClose}
            title={`Are you sure you want to vote "${support}" on bill ${bill.firestoreId}?\n\n\rLike votes cast by legislators, all votes through Sway are final.`}
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
