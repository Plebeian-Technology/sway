/** @format */

import { Support } from "@sway/constants";
import {
    Checkbox,
    createStyles,
    makeStyles,
    Theme,
    Typography
} from "@material-ui/core";
import { sway } from "sway";
import React from "react";
import { swayWhite } from "../../utils";
import { get } from "@sway/utils"

interface IProps {
    legislator: sway.ILegislator;
    values: sway.IPlainObject;
    touched: sway.IPlainObject;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    setTouched: (values: Record<string, unknown>) => void;
    style?: sway.IPlainObject;
}

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        root: {
            color: swayWhite,
            '&$checked': {
                color: swayWhite,
            },
        },
        legislatorPositionContainer: {
            border: `2px solid ${swayWhite}`,
            borderRadius: "3px",
            color: swayWhite,
            padding: theme.spacing(1),
            margin: theme.spacing(1),
        },
    })
);

const LegislatorPositionInput: React.FC<IProps> = ({
    legislator,
    values,
    touched,
    setFieldValue,
    setTouched,
}) => {
    const classes = useStyles();

    const fieldname = legislator.externalId;
    const position = get(values?.legislators, fieldname);

    return (
        <div className={classes.legislatorPositionContainer}>
            <Typography component={"p"} variant={"body1"}>
                {legislator.full_name}
            </Typography>
            <Typography component={"span"} variant={"body2"}>
                {Support.For}
            </Typography>
            <Checkbox
                className={classes.root}
                onChange={() => {
                    setTouched({
                        ...touched,
                        [`legislators.${legislator.externalId}`]: true,
                    });
                    setFieldValue(
                        `legislators.${legislator.externalId}`,
                        Support.For
                    );
                }}
                checked={position === Support.For}
                name={`legislators.${fieldname}`}
            />
            <Typography component={"span"} variant={"body2"}>
                {Support.Against}
            </Typography>
            <Checkbox
                className={classes.root}
                onChange={() => {
                    setTouched({
                        ...touched,
                        [`legislators.${legislator.externalId}`]: true,
                    });
                    setFieldValue(
                        `legislators.${legislator.externalId}`,
                        Support.Against
                    );
                }}
                checked={position === Support.Against}
                name={`legislators.${fieldname}`}
            />
            <Typography component={"span"} variant={"body2"}>
                {Support.Abstain}
            </Typography>
            <Checkbox
                className={classes.root}
                onChange={() => {
                    setTouched({
                        ...touched,
                        [`legislators.${legislator.externalId}`]: true,
                    });
                    setFieldValue(
                        `legislators.${legislator.externalId}`,
                        Support.Abstain
                    );
                }}
                checked={position === Support.Abstain}
                name={`legislators.${fieldname}`}
            />
        </div>
    );
};

export default LegislatorPositionInput;
