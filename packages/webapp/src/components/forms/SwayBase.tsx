/** @format */

import { createStyles, makeStyles, Theme } from "@material-ui/core";
import { sway } from "sway";
import React from "react";
import { IS_MOBILE_PHONE } from "../../utils";

interface IProps {
    children: React.ReactNode;
    style?: sway.IPlainObject;
}

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        fieldContainer: {
            display: "flex",
            flexDirection: "column",
            width: "47%",
            margin: theme.spacing(1),
            position: "relative",
        },
        mobileFieldContainer: {
            display: "flex",
            flexDirection: "column",
            margin: theme.spacing(1),
            position: "relative",
        },
        field: {
            marginBottom: theme.spacing(1),
        },
    })
);

const SwayBase: React.FC<IProps> = (props) => {
    const classes = useStyles();

    return (
        <div
            className={
                IS_MOBILE_PHONE
                    ? classes.mobileFieldContainer
                    : classes.fieldContainer
            }
            style={props.style && props.style}
        >
            {props.children}
        </div>
    );
};

export default SwayBase;
