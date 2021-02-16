/** @format */

import { Support } from "@sway/constants";
import {
    Button
} from "@material-ui/core";
import { Check, Clear } from "@material-ui/icons";
import { sway } from "sway";
import React from "react";
import {
    swayGray
} from "../../utils";

interface IState {
    support: string | null;
    dialog: boolean;
    isSubmitting: boolean;
}

interface IProps {
    user: sway.IUser | undefined;
    dialog: boolean;
    support: string | null;
    setState: React.Dispatch<React.SetStateAction<IState>>;
}

const VoteButtons: React.FC<IProps> = ({ dialog, user, support, setState }) => {
    const disable = dialog || !user?.uid || !user?.isRegistrationComplete;

    const handleVote = (clickedSupport: string) => {
        setState((prevState: IState) => ({
            ...prevState,
            dialog: true,
            support: clickedSupport,
        }));
    };

    const forButtonClasses = () => {
        if (disable) return "disabled";
        if (support === Support.For) {
            return "for selected";
        }
        return "for not-selected";
    };

    const againstButtonClasses = () => {
        if (disable) return "disabled";
        if (support === Support.Against) {
            return "against selected";
        }
        return "against not-selected";
    };

    const border = disable ? { border: `2px solid ${swayGray}` } : {}

    return (
        <>
            <Button
                style={border}
                onClick={() => handleVote(Support.For)}
                className={forButtonClasses()}
                startIcon={<Check />}
                disabled={disable || !!support}
            >
                {"For"}
            </Button>
            <Button
                style={border}
                onClick={() => handleVote(Support.Against)}
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
