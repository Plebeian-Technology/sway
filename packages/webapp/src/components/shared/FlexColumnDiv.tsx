import { createStyles, makeStyles } from "@material-ui/core";
import { sway } from "sway";

const useStyles = makeStyles(() =>
    createStyles({
        div: ({ style }: { style: sway.IPlainObject | undefined }) => ({
            display: "flex",
            flexDirection: "column",
            ...style,
        }),
    }),
);

const FlexColumnDiv: React.FC<{
    children: React.ReactNode;
    style?: sway.IPlainObject;
}> = ({ children, style }) => {
    const classes = useStyles({ style });

    return <div className={classes.div}>{children}</div>;
};

export default FlexColumnDiv;
