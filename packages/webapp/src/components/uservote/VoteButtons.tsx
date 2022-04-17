/** @format */

import { Check, Clear } from "@mui/icons-material";
import { Button } from "@mui/material";
import { makeStyles } from "@mui/styles";
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
    for: ({ support }: { support: TSupport }) => ({
        color: support === Support.For ? SWAY_COLORS.white : SWAY_COLORS.success,
        backgroundColor: support === Support.For ? SWAY_COLORS.success : SWAY_COLORS.white,
        borderColor: support === Support.For ? SWAY_COLORS.white : SWAY_COLORS.success,
        "&:hover": {
            borderColor: support === Support.For ? SWAY_COLORS.white : SWAY_COLORS.success,
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
        color: support === Support.Against ? SWAY_COLORS.white : SWAY_COLORS.tertiary,
        backgroundColor: support === Support.Against ? SWAY_COLORS.tertiary : SWAY_COLORS.white,
        borderColor: support === Support.Against ? SWAY_COLORS.white : SWAY_COLORS.tertiary,
        "&:hover": {
            borderColor: support === Support.Against ? SWAY_COLORS.white : SWAY_COLORS.tertiary,
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
        <div className="row my-2">
            <div className="col">
                <Button
                    disabled={disabled || !!support}
                    classes={{
                        root: classes.for,
                    }}
                    variant="outlined"
                    className="w-100 p-3"
                    onClick={() => handleVote(Support.For as "for")}
                    startIcon={<Check />}
                >
                    For
                </Button>
            </div>
            <div className="col">
                <Button
                    disabled={disabled || !!support}
                    classes={{
                        root: classes.against,
                    }}
                    variant="outlined"
                    className="w-100 p-3"
                    onClick={() => handleVote(Support.Against as "against")}
                    startIcon={<Clear />}
                >
                    Against
                </Button>
            </div>
        </div>
    );
};

export default VoteButtons;
