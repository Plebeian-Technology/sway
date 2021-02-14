import { Avatar, Backdrop } from "@material-ui/core";
import { Close } from "@material-ui/icons";
import { AWARD_ICONS_BY_TYPE } from "@sway/constants";
import { useState } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import "../../../scss/confetti.scss";
import Confetti from "./Confetti";


interface IProps {
    user: sway.IUser;
    userVotesCount: number;
}

/**
 *
 *
 * @param {IProps} { user, userVotesCount }
 * @return {JSX.Element}  {JSX.Element}
 */
const NewUserVoteAward = ({ user, userVotesCount }: IProps): JSX.Element => {
    const [open, setOpen] = useState<boolean>(true);

    const getAwardIcon = () => {
        if (userVotesCount > 0) {
            return AWARD_ICONS_BY_TYPE.Vote.blue;
        }
        if (userVotesCount > 9) {
            return AWARD_ICONS_BY_TYPE.Vote.red;
        }
        if (userVotesCount > 99) {
            return AWARD_ICONS_BY_TYPE.Vote.black;
        }
        if (userVotesCount > 999) {
            return AWARD_ICONS_BY_TYPE.Vote.silver;
        }
        if (userVotesCount > 9999) {
            return AWARD_ICONS_BY_TYPE.Vote.gold;
        }
        return null;
    };
    const getNextAwardIcon = () => {
        if (userVotesCount > 0) {
            return AWARD_ICONS_BY_TYPE.Vote.red;
        }
        if (userVotesCount > 9) {
            return AWARD_ICONS_BY_TYPE.Vote.black;
        }
        if (userVotesCount > 99) {
            return AWARD_ICONS_BY_TYPE.Vote.silver;
        }
        if (userVotesCount > 999) {
            return AWARD_ICONS_BY_TYPE.Vote.gold;
        }
        if (userVotesCount > 9999) {
            return null;
        }
        return null;
    };

    const closeConfetti = () => {
        setOpen(false);
    }

    // Show newly earned icon
    // Show empties in progress to next icon
    // Show fulfilled progress to next icon



    return (
        <Backdrop
            id="confetti-backdrop"
            open={open}
        >
             <div className="confetti-close" onClick={closeConfetti}>
                {<Close style={{
                    width: "100px",
                    height: "100px",
                }} />}
            </div>
            <Animate
                play={true}
                duration={1}
                start={{ zIndex: 10000, opacity: 0, filter: "blur(5px)" }}
                end={{ zIndex: 10000, opacity: 1, filter: "blur(0)" }}
                complete={{ zIndex: 10000, opacity: 1, filter: "blur(0)" }}
            >
                <Confetti closeConfetti={closeConfetti}>
                    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center" }}>
                        <h1 style={{ margin: 10, color: "white" }}>Congratulations!</h1>
                        <Avatar
                            src={AWARD_ICONS_BY_TYPE.Vote.blue}
                            style={{ width: 300, height: 300 }}
                        />
                        <h1 style={{ margin: 10, color: "white" }}>You gained some Sway.</h1>
                    </div>
                </Confetti>
            </Animate>
        </Backdrop>
    );
};

export default NewUserVoteAward;
