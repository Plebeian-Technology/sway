import { createStyles, makeStyles } from "@material-ui/core";
import { sway } from "sway";

const useStyles = makeStyles(() =>
    createStyles({
        div: (style: sway.IPlainObject | undefined) => ({
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            alignItems: "center",
            ...style,
        }),
    }),
);

const CenteredDivCol: React.FC<{
    children: React.ReactNode;
    style?: sway.IPlainObject;
    onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
}> = ({ children, onClick, style }) => {
    const classes = useStyles(style);

    return (
        <div
            onClick={onClick ? onClick : () => null}
            className={`${classes.div} centered-div-col`}
        >
            {children}
        </div>
    );
};

export default CenteredDivCol;
