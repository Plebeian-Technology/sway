/** @format */

import { makeStyles } from "@mui/styles";
import { Button, TextField } from "@mui/material";
import Autocomplete from "@mui/material/Autocomplete";
import { CATEGORIES } from "@sway/constants";
import React from "react";
import {
    IS_MOBILE_PHONE,
    SWAY_COLORS,
    swayDarkBlue,
    swayWhite,
} from "../../utils";

interface IProps {
    categories: string[];
    setCategories: (categories: string[]) => void;
}

const useStyles = makeStyles({
    table: { width: "95%", margin: "0 auto", textAlign: "center" },
    tableCell: {
        border: `1px solid ${swayDarkBlue}`,
        margin: 0,
        "&:hover": {
            borderColor: SWAY_COLORS.primary,
        },
    },
    button: {
        width: "100%",
        padding: 10,
        boxSizing: "border-box",
        fontWeight: "bold",
        backgroundColor: "transparent",
        color: swayDarkBlue,
        borderRadius: 0,
        "&:hover": {
            backgroundColor: SWAY_COLORS.primary,
            color: swayWhite,
        },
    },
    buttonSelected: {
        backgroundColor: swayDarkBlue,
        color: swayWhite,
        "&:hover": {
            backgroundColor: SWAY_COLORS.primary,
        },
    },
});

const BillsListCategoriesHeader: React.FC<IProps> = ({
    categories,
    setCategories,
}) => {
    const classes = useStyles();

    const updateCategories = (category: string) => {
        if (!category) return;

        if (categories.includes(category)) {
            return setCategories(
                categories.filter((c: string) => c !== category),
            );
        }
        setCategories(categories.concat(category));
    };

    const handleChangeCategory = (
        _event: React.ChangeEvent<any>,
        newValue: string[],
    ) => {
        if (!newValue) return;
        setCategories(newValue);
    };

    if (IS_MOBILE_PHONE) {
        return (
            <div>
                <Autocomplete
                    multiple
                    className="mt-1"
                    options={CATEGORIES}
                    getOptionLabel={(option) => option}
                    value={categories || []}
                    onChange={handleChangeCategory}
                    renderInput={(params) => (
                        <TextField
                            {...params}
                            variant="outlined"
                            label="Categories"
                            placeholder="Categories"
                        />
                    )}
                />
            </div>
        );
    }

    return (
        <table className={classes.table}>
            <thead>
                <tr>
                    {CATEGORIES.map((category: string) => {
                        const buttonClass = categories.includes(category)
                            ? `${classes.button} ${classes.buttonSelected}`
                            : classes.button;
                        return (
                            <td key={category} className={classes.tableCell}>
                                <Button
                                    className={buttonClass}
                                    onClick={() => updateCategories(category)}
                                >
                                    {category}
                                </Button>
                            </td>
                        );
                    })}
                </tr>
            </thead>
        </table>
    );
};

export default BillsListCategoriesHeader;
