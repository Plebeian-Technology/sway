import { createStyles, makeStyles } from "@material-ui/core";
import { sway } from "sway";

const useStyles = makeStyles(() =>
    createStyles({
        div: {
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            alignItems: "center",
        },
    }),
);

const CenteredDivCol: React.FC<{
    children: (JSX.Element | null)[] | JSX.Element | null;
    style?: sway.IPlainObject;
}> = ({ children, style }) => {
    const classes = useStyles();

    const _style = style ? style : {};

    return <div style={_style} className={`${classes.div} centered-div-row`}>{children}</div>;
};

export default CenteredDivCol;
