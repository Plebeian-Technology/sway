import { Avatar, createStyles, makeStyles } from "@material-ui/core";
import { ArrowForwardIos } from "@material-ui/icons";
import { titleize } from "@sway/utils";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import "../../../scss/confetti.scss";
import { AWARD_ICONS_BY_TYPE, SWAY_COLORS } from "../../../utils";
import FlexRowDiv from "../../shared/FlexRowDiv";
import { AwardTooltip } from "./UserAwardsRow";

const AwardTooltipAvatar: React.FC<{
    title: string;
    iconPath: string;
    className?: string;
    style?: sway.IPlainObject;
}> = ({ title, iconPath, style, className }) => (
    <AwardTooltip title={title} placement="bottom">
        <Avatar
            src={iconPath}
            className={className || ""}
            style={style ? { ...style } : {}}
        />
    </AwardTooltip>
);

interface IProps {
    locale: sway.IUserLocale | sway.ILocale;
    awardCount: number;
    currentMaximum: number;
    currentIcon: string;
    getAwardIcon: () => string;
    type: sway.TAwardType;
}

const useStyles = makeStyles(() =>
    createStyles({
        container: {
            display: "flex",
            flexDirection: "row",
            flexWrap: "wrap",
            justifyContent: "space-evenly",
            alignItems: "flex-start",
        },
        miniAvatar: {
            width: 50,
            height: 50,
            margin: 3,
            border: "2px solid transparent",
        },
    }),
);

const AwardProgressBar: React.FC<IProps> = ({
    locale,
    awardCount,
    currentMaximum,
    currentIcon,
    getAwardIcon,
    type,
}) => {
    const classes = useStyles();

    const zIndex = 10000;
    const endStyle = {
        zIndex,
        opacity: 1,
        filter: "blur(0) grayscale(0)",
    };

    const getNextCount = () => {
        if (awardCount < 10) {
            return 10;
        }
        if (awardCount < 100) {
            return 100;
        }
        if (awardCount < 1000) {
            return 1000;
        }
        if (awardCount < 10000) {
            return 10000;
        }
        return 100000;
    };

    const getNextAwardIcon = () => {
        if (awardCount < 10) {
            return AWARD_ICONS_BY_TYPE[type].icons.red;
        }
        if (awardCount < 100) {
            return AWARD_ICONS_BY_TYPE[type].icons.black;
        }
        if (awardCount < 1000) {
            return AWARD_ICONS_BY_TYPE[type].icons.silver;
        }
        if (awardCount < 10000) {
            return AWARD_ICONS_BY_TYPE[type].icons.gold;
        }
        if (awardCount < 100000) {
            return null;
        }
        return null;
    };

    const nextIcon = getNextAwardIcon();

    const tooltip = AWARD_ICONS_BY_TYPE[type].tooltip(
        currentMaximum,
        titleize(locale.city),
    );

    const nextTooltip = AWARD_ICONS_BY_TYPE[type].nextTooltip(
        getNextCount(),
        titleize(locale.city),
    );

    const progressRow = new Array(10)
        .fill(null)
        .map((empty: null, i: number) => {
            if (awardCount / currentMaximum - 1 === i) {
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
                            title={tooltip}
                            iconPath={currentIcon}
                            className={classes.miniAvatar}
                            style={{
                                border: `2px solid ${SWAY_COLORS.success}`,
                            }}
                        />
                    </Animate>
                );
            }

            if (i < awardCount / currentMaximum - 1) {
                return (
                    <AwardTooltipAvatar
                        key={i}
                        title={tooltip}
                        iconPath={currentIcon}
                        className={classes.miniAvatar}
                    />
                );
            }
            return (
                <Avatar
                    key={i}
                    src={getAwardIcon()}
                    className={classes.miniAvatar}
                    style={{
                        filter: "grayscale(100%)",
                    }}
                />
            );
        });

    return (
        <FlexRowDiv className={classes.container}>
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
                    title={nextTooltip}
                    placement="bottom"
                    style={{
                        color: "white",
                        filter: "grayscale(0)",
                    }}
                >
                    <Avatar src={nextIcon} className={classes.miniAvatar} />
                </AwardTooltip>
            )}
        </FlexRowDiv>
    );
};

export default AwardProgressBar;
