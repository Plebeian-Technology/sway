import {} from "@mui/material";
import { makeStyles } from "@mui/styles";
import { sway } from "sway";

const useStyles = makeStyles({
    div: (style: sway.IPlainObject | undefined) => ({
        display: "flex",
        flexDirection: "row",
        justifyContent: "center",
        alignItems: "center",
        ...style,
    }),
});

const CenteredDivRow: React.FC<{
    children: React.ReactNode;
    style?: sway.IPlainObject;
    onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
}> = ({ children, onClick, style }) => {
    const classes = useStyles(style);

    return (
        <div
            onClick={onClick ? onClick : () => null}
            className={`${classes.div} centered-div-row`}
        >
            {children}
        </div>
    );
};

export default CenteredDivRow;
