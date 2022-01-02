/** @format */

import { Button } from "@mui/material";
import { makeStyles } from "@mui/styles";
import { Check, Clear } from "@mui/icons-material";
import { Support } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";

type TSupport = "for" | "against" | null;

interface IState {
    support: TSupport;
    dialog: boolean;
    isSubmitting: boolean;
}

interface IProps {
    user: sway.IUser | undefined;
    dialog: boolean;
    support: TSupport;
    setState: React.Dispatch<React.SetStateAction<IState>>;
}

const useStyles = makeStyles({
    button: () => ({
        width: "40%",
        padding: "1em",
        margin: "1em",
        fontWeight: 700,
        border: "2px solid",
    }),
    for: ({ support }: { support: TSupport }) => ({
        color:
            support === Support.For ? SWAY_COLORS.white : SWAY_COLORS.success,
        backgroundColor:
            support === Support.For ? SWAY_COLORS.success : SWAY_COLORS.white,
        borderColor:
            support === Support.For ? SWAY_COLORS.white : SWAY_COLORS.success,
        "&:hover": {
            color: SWAY_COLORS.white,
            background: SWAY_COLORS.success,
        },
        "&:disabled": {
            borderColor: "initial",
            color:
                support === Support.For
                    ? SWAY_COLORS.white
                    : support
                    ? SWAY_COLORS.success
                    : "initial",
        },
    }),
    against: ({ support }: { support: TSupport }) => ({
        color:
            support === Support.Against
                ? SWAY_COLORS.white
                : SWAY_COLORS.tertiary,
        backgroundColor:
            support === Support.Against
                ? SWAY_COLORS.tertiary
                : SWAY_COLORS.white,
        borderColor:
            support === Support.Against
                ? SWAY_COLORS.white
                : SWAY_COLORS.tertiary,
        "&:hover": {
            color: SWAY_COLORS.white,
            background: SWAY_COLORS.tertiary,
        },
        "&:disabled": {
            borderColor: "initial",
            color:
                support === Support.Against
                    ? SWAY_COLORS.white
                    : support
                    ? SWAY_COLORS.tertiary
                    : "initial",
        },
    }),
});

const VoteButtons: React.FC<IProps> = ({ dialog, user, support, setState }) => {
    const disabled = dialog || !user?.uid || !user?.isRegistrationComplete;
    const classes = useStyles({ support });

    const handleVote = (clickedSupport: "for" | "against") => {
        setState((prevState: IState) => ({
            ...prevState,
            dialog: true,
            support: clickedSupport,
        }));
    };

    return (
        <>
            <Button
                disabled={disabled || !!support}
                classes={{
                    root: `${classes.button} ${classes.for}`,
                }}
                onClick={() => handleVote(Support.For as "for")}
                startIcon={<Check />}
            >
                {"For"}
            </Button>
            <Button
                disabled={disabled || !!support}
                classes={{
                    root: `${classes.button} ${classes.against}`,
                }}
                onClick={() => handleVote(Support.Against as "against")}
                startIcon={<Clear />}
            >
                {"Against"}
            </Button>
        </>
    );
};

export default VoteButtons;
