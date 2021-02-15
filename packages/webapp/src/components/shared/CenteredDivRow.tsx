import { createStyles, makeStyles } from "@material-ui/core";

const useStyles = makeStyles(() =>
    createStyles({
        div: {
            display: "flex",
            flexDirection: "row",
            justifyContent: "center",
            alignItems: "center",
        },
    }),
);

const CenteredDivRow: React.FC<{
    children: (JSX.Element | null)[] | JSX.Element | null;
}> = ({ children }) => {
    const classes = useStyles();

    return <div className={`${classes.div} centered-div-row`}>{children}</div>;
};

export default CenteredDivRow;
