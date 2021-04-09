/** @format */

import {
    createStyles,
    Link as MaterialLink,
    makeStyles,
    Typography,
} from "@material-ui/core";
import { ROUTES } from "@sway/constants";
import React from "react";
import { useHistory } from "react-router-dom";
import { IS_MOBILE_PHONE } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";

const useStyles = makeStyles(() => {
    return createStyles({
        pointer: {
            cursor: "pointer",
            lineHeight: 2
        },
    });
});

const BillActionLinks: React.FC = () => {
    const history = useHistory();
    const classes = useStyles();

    const handleNavigate = (pathname: string) => {
        history.push({ pathname });
    };

    const Component = IS_MOBILE_PHONE ? CenteredDivCol : CenteredDivRow;

    return (
        <Component
            style={{ marginTop: 20, marginBottom: 20, flexWrap: "nowrap", textAlign: "center", lineHeight: 1.5 }}
        >
            <Typography>
                <MaterialLink
                    className={classes.pointer}
                    onClick={() => handleNavigate(ROUTES.legislators)}
                >
                    {"See how you compare to your representatives"}
                </MaterialLink>
                {" or "}
                <MaterialLink
                    className={classes.pointer}
                    onClick={() => handleNavigate(ROUTES.pastBills)}
                >
                    {"vote on past legislatiion."}
                </MaterialLink>
                </Typography>
        </Component>
    );
};

export default BillActionLinks;
