/** @format */

import { CATEGORIES } from "@sway/constants";
import { logDev } from "@sway/utils";
import React, { useCallback, useMemo } from "react";
import { Button, Form } from "react-bootstrap";
import Select, { MultiValue } from "react-select";
import { IS_MOBILE_PHONE, REACT_SELECT_STYLES } from "../../utils";

interface IProps {
    categories: string[];
    setCategories: (categories: string[]) => void;
}

const BillsListCategoriesHeader: React.FC<IProps> = ({ categories, setCategories }) => {
    const updateCategories = (category: string) => {
        if (!category) return;

        if (categories.includes(category)) {
            return setCategories(categories.filter((c: string) => c !== category));
        }
        setCategories(categories.concat(category));
    };

    const handleChangeCategory = useCallback(
        (values: MultiValue<{ label: string; value: string }>) => {
            logDev("BillsListCategoriesHeader.handleChange newValue -", values);
            if (!values) return;
            setCategories(values.map((v) => v.value));
        },
        [],
    );

    const toSelecOption = useCallback((value: string) => ({ label: value, value }), []);
    const options = useMemo(() => CATEGORIES.map(toSelecOption), []);

    logDev("BillsListCategoriesHeader.categories -", categories);

    if (IS_MOBILE_PHONE) {
        return (
            <Form.Group controlId="bill-categories" className="mt-2">
                <Select
                    onChange={handleChangeCategory}
                    value={categories.map(toSelecOption)}
                    options={options}
                    isMulti
                    isClearable
                    placeholder="Filter by category"
                    styles={REACT_SELECT_STYLES}
                />
            </Form.Group>
        );
    }

    return (
        <table className="w-100 mt-2">
            <thead>
                <tr>
                    {CATEGORIES.map((category: string, i: number) => {
                        const isSelected = categories.includes(category);
                        return (
                            <th
                                key={category}
                                className={`${
                                    i === 0
                                        ? "text-start"
                                        : i === CATEGORIES.length - 1
                                        ? "text-end"
                                        : "text-center"
                                }`}
                            >
                                <Button
                                    onClick={() => updateCategories(category)}
                                    variant={isSelected ? "primary" : "outline-primary"}
                                >
                                    {category}
                                </Button>
                            </th>
                        );
                    })}
                </tr>
            </thead>
        </table>
    );
};

export default BillsListCategoriesHeader;
