import { Avatar, Backdrop, createStyles, makeStyles } from "@material-ui/core";
import { Close } from "@material-ui/icons";
import { useRef } from "react";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks";
import { useAwardCount } from "../../../hooks/awards";
import "../../../scss/confetti.scss";
import { AWARD_ICONS_BY_TYPE, SWAY_COLORS } from "../../../utils";
import Confetti from "../../dialogs/Confetti";
import CenteredDivCol from "../../shared/CenteredDivCol";
import AwardProgressBar from "./AwardProgressBar";

interface IProps {
    user: sway.IUser;
    locale: sway.IUserLocale | sway.ILocale;
    type: sway.TAwardType;
    setIsCongratulations: (congratulations: boolean) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        bigAvatar: { width: 300, height: 300 },
        text: {
            margin: 10,
            color: SWAY_COLORS.white,
            fontWeight: "bold",
            textAlign: "center",
        },
    }),
);

/**
 * @param {IProps} { user, locale, type }
 * @return {JSX.Element}  {JSX.Element}
 */
const Award: React.FC<IProps> = ({
    user,
    locale,
    type,
    setIsCongratulations,
}): JSX.Element | null => {
    const ref = useRef(null);
    const classes = useStyles();
    const [open, setOpen] = useOpenCloseElement(ref, true);

    const awardCount = useAwardCount(user, locale, type);
    if (awardCount < 0) {
        return null;
    }

    const getCurrentMaximum = () => {
        if (awardCount > 9999) {
            return 10000;
        }
        if (awardCount > 999) {
            return 1000;
        }
        if (awardCount > 99) {
            return 100;
        }
        if (awardCount > 9) {
            return 10;
        }
        return 1;
    };

    const getAwardIcon = () => {
        if (awardCount < 10) {
            return AWARD_ICONS_BY_TYPE[type].icons.blue;
        }
        if (awardCount < 100) {
            return AWARD_ICONS_BY_TYPE[type].icons.red;
        }
        if (awardCount < 1000) {
            return AWARD_ICONS_BY_TYPE[type].icons.black;
        }
        if (awardCount < 10000) {
            return AWARD_ICONS_BY_TYPE[type].icons.silver;
        }
        return AWARD_ICONS_BY_TYPE[type].icons.gold;
    };

    const closeConfetti = () => {
        setOpen(false);
        setIsCongratulations(false);
    };

    const zIndex = 10000;
    const endStyle = {
        zIndex,
        opacity: 1,
        filter: "blur(0) grayscale(0)",
    };

    const currentIcon = getAwardIcon();
    const currentMaximum = getCurrentMaximum();

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
                    <CenteredDivCol
                        style={{
                            width: "100%",
                            height: "100%",
                        }}
                    >
                        <h1 className={classes.text}>Congratulations!</h1>
                        <Avatar
                            src={AWARD_ICONS_BY_TYPE[type].icons.blue}
                            className={classes.bigAvatar}
                        />
                        <h1 className={classes.text}>You gained some Sway.</h1>
                        <AwardProgressBar
                            locale={locale}
                            awardCount={awardCount}
                            currentMaximum={currentMaximum}
                            currentIcon={currentIcon}
                            getAwardIcon={getAwardIcon}
                            type={type}
                        />
                        <p className={classes.text} style={{ marginTop: 50 }}>
                            {
                                "(If you find this annoying you can stop it in Settings -> Congratulations Settings)"
                            }
                        </p>
                    </CenteredDivCol>
                </Confetti>
            </Animate>
        </Backdrop>
    );
};

export default Award;
