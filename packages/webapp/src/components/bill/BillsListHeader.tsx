/** @format */

import {
    Button,
    createStyles,
    makeStyles,
    TextField
} from "@material-ui/core";
import { Autocomplete } from "@material-ui/lab";
import { CATEGORIES } from "@sway/constants";
import React from "react";
import { isMobilePhone, SWAY_COLORS, swayDarkBlue, swayWhite } from "../../utils";

interface IProps {
    categories: string[];
    setCategories: (categories: string[]) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        table: { width: "95%", margin: "0 auto", textAlign: "center" },
        tableCell: {
            border: `1px solid ${swayDarkBlue}`,
            margin: 0,
            "&:hover": {
                borderColor: SWAY_COLORS.primary,
            }
        },
        button: {
            width: "100%",
            padding: "10px",
            boxSizing: "border-box",
            fontWeight: "bold",
            backgroundColor: "transparent",
            color: swayDarkBlue,
            borderRadius: 0,
            "&:hover": {
                backgroundColor: SWAY_COLORS.primary,
                color: swayWhite,
            }
        },
        buttonSelected: {
            backgroundColor: swayDarkBlue,
            color: swayWhite,
            "&:hover": {
                backgroundColor: SWAY_COLORS.primary,
            }
        },
    })
);

const BillsListHeader: React.FC<IProps> = ({ categories, setCategories }) => {
    const classes = useStyles();

    const updateCategories = (category: string) => {
        if (!category) return;

        if (categories.includes(category)) {
            return setCategories(
                categories.filter((c: string) => c !== category)
            );
        }
        setCategories(categories.concat(category));
    }

    const handleChangeCategory = (event: React.ChangeEvent<Record<string, unknown>>, newValue: string[] | null) => {
        if (!newValue) return;
        setCategories(newValue);
    }

    if (isMobilePhone) {
        return (
            <div style={{ backgroundColor: swayDarkBlue, padding: "10px" }}>
                <Autocomplete
                    multiple
                    options={CATEGORIES}
                    getOptionLabel={(option) => option}
                    value={categories || []}
                    onChange={handleChangeCategory}
                    style={{ margin: "10px" }}
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
                        const buttonClass = categories.includes(category) ? `${classes.button} ${classes.buttonSelected}` : classes.button
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

export default BillsListHeader;
