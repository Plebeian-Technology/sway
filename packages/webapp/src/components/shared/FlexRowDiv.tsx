import {} from "@mui/material";
import { makeStyles } from "@mui/styles";
import { sway } from "sway";

const useStyles = makeStyles({
    div: ({
        justifyContent,
        alignItems,
        style,
    }: {
        justifyContent: string;
        alignItems: string;
        style: sway.IPlainObject;
    }) => ({
        display: "flex",
        flexDirection: "row",
        justifyContent,
        alignItems,
        ...style,
    }),
});

const FlexRowDiv: React.FC<{
    children: React.ReactNode;
    justifyContent?: string;
    alignItems?: string;
    className?: string;
    style?: sway.IPlainObject;
}> = ({ children, className, alignItems, justifyContent, style }) => {
    const _style = style ? style : {};
    const classes = useStyles({
        alignItems: alignItems || "flex-start",
        justifyContent: justifyContent || "flex-start",
        style: _style,
    });

    const klass = className ? className : "";

    return (
        <div
            style={_style}
            className={`${klass} ${classes.div} centered-div-row`}
        >
            {children}
        </div>
    );
};

export default FlexRowDiv;
