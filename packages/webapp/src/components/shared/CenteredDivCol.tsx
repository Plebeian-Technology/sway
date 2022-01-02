import {} from "@mui/material";
import { makeStyles } from "@mui/styles";
import { sway } from "sway";

const useStyles = makeStyles({
    div: (style: sway.IPlainObject | undefined) => ({
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        alignItems: "center",
        ...style,
    }),
});

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
