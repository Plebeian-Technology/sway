/** @format */

import { Link as MaterialLink, Typography } from "@mui/material";
import { makeStyles } from "@mui/styles";
import { ROUTES } from "@sway/constants";
import React from "react";
import { useNavigate } from "react-router-dom";
import { IS_MOBILE_PHONE } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";

const useStyles = makeStyles({
    pointer: {
        cursor: "pointer",
        lineHeight: 2,
    },
});

const BillActionLinks: React.FC = () => {
    const navigate = useNavigate();
    const classes = useStyles();

    const handleNavigate = (pathname: string) => {
        navigate({ pathname });
    };

    const Component = IS_MOBILE_PHONE ? CenteredDivCol : CenteredDivRow;

    return (
        <Component
            style={{
                marginTop: 20,
                marginBottom: 20,
                flexWrap: "nowrap",
                textAlign: "center",
                lineHeight: 1.5,
            }}
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
