import { Avatar, Backdrop } from "@material-ui/core";
import { ArrowForwardIos, Close } from "@material-ui/icons";
import { AWARD_ICONS_BY_TYPE } from "@sway/constants";
import { titleize } from "@sway/utils";
import { useRef } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { useUserVotesCount } from "../../../hooks/user_votes";
import "../../../scss/confetti.scss";
import { SWAY_COLORS } from "../../../utils";
import { AwardTooltip } from "../../user/UserAwardsRow";
import Confetti from "./Confetti";

interface IProps {
    user: sway.IUser;
    locale: sway.IUserLocale | sway.ILocale;
}

const AwardTooltipAvatar: React.FC<{
    title: string;
    iconPath: string;
    style: sway.IPlainObject;
}> = ({ title, iconPath, style }) => (
    <AwardTooltip title={title} placement="bottom">
        <Avatar src={iconPath} style={{ ...style }} />
    </AwardTooltip>
);

/**
 * @param {IProps} { user, userVotesCount }
 * @return {JSX.Element}  {JSX.Element}
 */
const NewUserVoteAward = ({ user, locale }: IProps): JSX.Element | null => {
    const ref = useRef(null);
    const [open, setOpen] = useOpenCloseElement(ref, true);
    const userVotesCount = useUserVotesCount(user, locale);

    if (userVotesCount < 0) {
        return null;
    }

    const getCurrentMaximum = () => {
        if (userVotesCount > 9999) {
            return 10000;
        }
        if (userVotesCount > 999) {
            return 1000;
        }
        if (userVotesCount > 99) {
            return 100;
        }
        if (userVotesCount > 9) {
            return 10;
        }
        return 1;
    };

    const getNextCount = () => {
        if (userVotesCount < 10) {
            return 10;
        }
        if (userVotesCount < 100) {
            return 100;
        }
        if (userVotesCount < 1000) {
            return 1000;
        }
        if (userVotesCount < 10000) {
            return 10000;
        }
        return 100000;
    };

    const getAwardIcon = () => {
        if (userVotesCount < 10) {
            return AWARD_ICONS_BY_TYPE.Vote.blue;
        }
        if (userVotesCount < 100) {
            return AWARD_ICONS_BY_TYPE.Vote.red;
        }
        if (userVotesCount < 1000) {
            return AWARD_ICONS_BY_TYPE.Vote.black;
        }
        if (userVotesCount < 10000) {
            return AWARD_ICONS_BY_TYPE.Vote.silver;
        }
        return AWARD_ICONS_BY_TYPE.Vote.gold;
    };

    const getNextAwardIcon = () => {
        if (userVotesCount < 10) {
            return AWARD_ICONS_BY_TYPE.Vote.red;
        }
        if (userVotesCount < 100) {
            return AWARD_ICONS_BY_TYPE.Vote.black;
        }
        if (userVotesCount < 1000) {
            return AWARD_ICONS_BY_TYPE.Vote.silver;
        }
        if (userVotesCount < 10000) {
            return AWARD_ICONS_BY_TYPE.Vote.gold;
        }
        if (userVotesCount < 100000) {
            return null;
        }
        return null;
    };

    const closeConfetti = () => {
        setOpen(false);
    };

    const zIndex = 10000;
    const endStyle = {
        zIndex,
        opacity: 1,
        filter: "blur(0) grayscale(0)",
    };
    const miniAvatarStyle = {
        width: 50,
        height: 50,
        margin: 3,
        border: "2px solid transparent",
    };

    const currentIcon = getAwardIcon();
    const nextIcon = getNextAwardIcon();
    const currentMaximum = getCurrentMaximum();
    const progressRow = new Array(10)
        .fill(null)
        .map((empty: null, i: number) => {
            if ((userVotesCount / currentMaximum) - 1 === i) {
                return (
                    <Animate
                        key={i}
                        play={true}
                        duration={2}
                        delay={0}
                        start={{
                            zIndex,
                            opacity: 1,
                            filter: "blur(5px) grayscale(100%)",
                        }}
                        end={{ ...endStyle }}
                        complete={{
                            ...endStyle,
                        }}
                    >
                        <AwardTooltipAvatar
                            title={`Voted on ${currentMaximum} bill(s) in ${titleize(
                                locale.city,
                            )}.`}
                            iconPath={currentIcon}
                            style={{
                                ...miniAvatarStyle,
                                border: `2px solid ${SWAY_COLORS.success}`,
                            }}
                        />
                    </Animate>
                );
            }

            if (i < (userVotesCount / currentMaximum) - 1) {
                return (
                    <AwardTooltipAvatar
                        key={i}
                        title={`Voted on ${currentMaximum} bill(s) in ${titleize(
                            locale.city,
                        )}.`}
                        iconPath={currentIcon}
                        style={{ ...miniAvatarStyle }}
                    />
                );
            }
            return (
                <Avatar
                    key={i}
                    src={getAwardIcon()}
                    style={{
                        ...miniAvatarStyle,
                        filter: "grayscale(100%)",
                    }}
                />
            );
        });

    const blurDelay = 0;
    const blurDuration = 1;

    return (
        <Backdrop
            ref={ref}
            id="confetti-backdrop"
            open={open}
            onKeyDown={closeConfetti}
            tabIndex={-1}
            onClick={closeConfetti}
        >
            <div className="confetti-close" onClick={closeConfetti}>
                {
                    <Close
                        style={{
                            width: "100px",
                            height: "100px",
                        }}
                    />
                }
            </div>
            <Animate
                play={true}
                duration={blurDuration}
                delay={blurDelay}
                start={{ zIndex, opacity: 0, filter: "blur(5px)" }}
                end={{ ...endStyle }}
                complete={{ ...endStyle }}
            >
                <Confetti>
                    <div
                        style={{
                            width: "100%",
                            height: "100%",
                            display: "flex",
                            flexDirection: "column",
                            justifyContent: "center",
                            alignItems: "center",
                        }}
                    >
                        <h1 style={{ margin: 10, color: "white" }}>
                            Congratulations!
                        </h1>
                        <Avatar
                            src={AWARD_ICONS_BY_TYPE.Vote.blue}
                            style={{ width: 300, height: 300 }}
                        />
                        <h1 style={{ margin: 10, color: "white" }}>
                            You gained some Sway.
                        </h1>
                        <div
                            style={{
                                display: "flex",
                                flexDirection: "row",
                                flexWrap: "wrap",
                                justifyContent: "space-evenly",
                                alignItems: "flex-start",
                            }}
                        >
                            {progressRow}
                            <div
                                style={{
                                    width: 20,
                                    height: 50,
                                    position: "relative",
                                    margin: 0,
                                    textAlign: "center",
                                }}
                            >
                                <ArrowForwardIos
                                    style={{
                                        color: "white",
                                        position: "relative",
                                        top: 18,
                                    }}
                                />
                            </div>
                            {nextIcon && (
                                <AwardTooltip
                                    title={`Vote on ${getNextCount()} bills in ${titleize(
                                        locale.city,
                                    )}.`}
                                    placement="bottom"
                                    style={{
                                        color: "white",
                                        filter: "grayscale(0)",
                                    }}
                                >
                                    <Avatar
                                        src={nextIcon}
                                        style={{ ...miniAvatarStyle }}
                                    />
                                </AwardTooltip>
                            )}
                        </div>
                    </div>
                </Confetti>
            </Animate>
        </Backdrop>
    );
};

export default NewUserVoteAward;
