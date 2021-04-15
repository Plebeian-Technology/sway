import { createStyles, makeStyles } from "@material-ui/core";
import { sway } from "sway";

const useStyles = makeStyles(() =>
    createStyles({
        div: ({
            justifyContent,
            alignItems,
            style,
        }: {
            justifyContent: string;
            alignItems: string;
            style: sway.IPlainObject | undefined;
        }) => ({
            display: "flex",
            flexDirection: "column",
            justifyContent,
            alignItems,
            ...style,
        }),
    }),
);

const FlexColumnDiv: React.FC<{
    children: React.ReactNode;
    alignItems?: string;
    justifyContent?: string;
    style?: sway.IPlainObject;
}> = ({ children, alignItems, justifyContent, style }) => {
    const classes = useStyles({
        alignItems: alignItems || "flex-start",
        justifyContent: justifyContent || "flex-start",
        style,
    });

    return <div className={classes.div}>{children}</div>;
};

export default FlexColumnDiv;
