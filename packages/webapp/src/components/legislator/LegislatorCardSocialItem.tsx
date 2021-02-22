import {
    createStyles,
    IconButton,
    makeStyles,
    SvgIconTypeMap,
    Tooltip,
    Typography,
} from "@material-ui/core";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import { IS_MOBILE_PHONE, SWAY_COLORS } from "../../utils";

interface IProps {
    title: string;
    text: string;
    handleCopy: (text: string) => void;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
}

const useStyles = makeStyles(() =>
    createStyles({
        copy: {
            cursor: "pointer",
        },
        copyIcon: {
            maxHeight: "2em",
        },
        container: {
            margin: 5,
            display: "flex",
            flexDirection: IS_MOBILE_PHONE ? "row" : "column",
            justifyContent: IS_MOBILE_PHONE ? "space-between" : "center",
            alignItems: "center",
            textAlign: IS_MOBILE_PHONE ? "left" : "center",
            width: "100%"
        },
        textContainer: {
            width: "100%",
        },
        iconsContainer: {
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-evenly",
            alignItems: "end",
        },
        item: {
            paddingRight: IS_MOBILE_PHONE ? 0 : 10,
            paddingLeft: 10,
            overflow: "hidden",
            textOverflow: "ellipsis",
        },
    }),
);

const LegislatorCardSocialItem: React.FC<IProps> = ({
    title,
    text,
    handleCopy,
    Icon,
}) => {
    const classes = useStyles();

    const setCopy = () => {
        handleCopy(text);
    };

    return (
        <div className={`${classes.container} ${classes.copy}`}>
            <div
                className={`${classes.textContainer} ${classes.item}`}
                onClick={setCopy}
            >
                <Typography variant={"body2"}>{text}</Typography>
            </div>
            <div className={classes.iconsContainer}>
                <div className={classes.item}>
                    <IconButton
                        style={{
                            padding: 8,
                            backgroundColor: SWAY_COLORS.primary,
                        }}
                    >
                        <Icon style={{ color: SWAY_COLORS.white }} />
                    </IconButton>
                </div>
                <Tooltip
                    title={`Copy ${title}`}
                    placement="right"
                    onClick={setCopy}
                >
                    <div className={classes.item}>
                        <img
                            alt={"Copy"}
                            src={"/copy.png"}
                            className={classes.copyIcon}
                        />
                    </div>
                </Tooltip>
            </div>
        </div>
    );
};

export default LegislatorCardSocialItem;
