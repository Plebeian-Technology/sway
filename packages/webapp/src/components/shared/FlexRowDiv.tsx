import { createStyles, makeStyles } from "@material-ui/core";
import { sway } from "sway";

const useStyles = makeStyles(() =>
    createStyles({
        div: {
            display: "flex",
            flexDirection: "row",
        },
    }),
);

const FlexRowDiv: React.FC<{
    children: React.ReactNode;
    className?: string;
    style?: sway.IPlainObject;
}> = ({ children, className, style }) => {
    const classes = useStyles();

    const _style = style ? style : {};
    const klass = className ? className : "";

    return (
        <div style={_style} className={`${klass} ${classes.div} centered-div-row`}>
            {children}
        </div>
    );
};

export default FlexRowDiv;
