/** @format */

import { Autocomplete } from "@mui/material";
import { makeStyles } from "@mui/styles";
import { CATEGORIES } from "@sway/constants";
import React from "react";
import { Button, Form } from "react-bootstrap";
import { IS_MOBILE_PHONE, SWAY_COLORS } from "../../utils";

interface IProps {
    categories: string[];
    setCategories: (categories: string[]) => void;
}

const useStyles = makeStyles({
    tableCell: {
        border: `1px solid ${SWAY_COLORS.primary}`,
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
        color: SWAY_COLORS.primary,
        borderRadius: 0,
        "&:hover": {
            backgroundColor: SWAY_COLORS.primary,
            color: SWAY_COLORS.white,
        },
    },
    buttonSelected: {
        backgroundColor: SWAY_COLORS.primary,
        color: SWAY_COLORS.white,
        "&:hover": {
            backgroundColor: SWAY_COLORS.primary,
        },
    },
});

const BillsListCategoriesHeader: React.FC<IProps> = ({ categories, setCategories }) => {
    const classes = useStyles();

    const updateCategories = (category: string) => {
        if (!category) return;

        if (categories.includes(category)) {
            return setCategories(categories.filter((c: string) => c !== category));
        }
        setCategories(categories.concat(category));
    };

    const handleChangeCategory = (_event: React.ChangeEvent<any>, newValue: string[]) => {
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
                        <Form.Group {...params}>
                            <Form.Label>Categories</Form.Label>
                            <Form.Control placeholder="Categories" />
                        </Form.Group>
                    )}
                />
            </div>
        );
    }

    return (
        <table className="w-100">
            <thead>
                <tr>
                    {CATEGORIES.map((category: string) => {
                        const isSelected = categories.includes(category);
                        const buttonClass = isSelected
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
