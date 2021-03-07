/** @format */

import { Button } from "@material-ui/core";
import { Check, Clear } from "@material-ui/icons";
import { Support } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";

interface IState {
    support: "for" | "against" | null;
    dialog: boolean;
    isSubmitting: boolean;
}

interface IProps {
    user: sway.IUser | undefined;
    dialog: boolean;
    support: "for" | "against" | null;
    setState: React.Dispatch<React.SetStateAction<IState>>;
}

const VoteButtons: React.FC<IProps> = ({ dialog, user, support, setState }) => {
    const disable = dialog || !user?.uid || !user?.isRegistrationComplete;

    const handleVote = (clickedSupport: "for" | "against") => {
        setState((prevState: IState) => ({
            ...prevState,
            dialog: true,
            support: clickedSupport,
        }));
    };

    const forButtonClasses = () => {
        if (disable || (support && support !== Support.For)) return "disabled";
        if (support === Support.For) {
            return "for selected";
        }
        return "for not-selected";
    };

    const againstButtonClasses = () => {
        if (disable || (support && support !== Support.Against)) return "disabled";
        if (support === Support.Against) {
            return "against selected";
        }
        return "against not-selected";
    };

    const border = disable
        ? { border: `2px solid ${SWAY_COLORS.secondaryDark}` }
        : {};

    return (
        <>
            <Button
                style={border}
                onClick={() => handleVote(Support.For as "for")}
                className={forButtonClasses()}
                startIcon={<Check />}
                disabled={disable || !!support}
            >
                {"For"}
            </Button>
            <Button
                style={border}
                onClick={() => handleVote(Support.Against as "against")}
                className={againstButtonClasses()}
                startIcon={<Clear />}
                disabled={disable || !!support}
            >
                {"Against"}
            </Button>
        </>
    );
};

export default VoteButtons;
