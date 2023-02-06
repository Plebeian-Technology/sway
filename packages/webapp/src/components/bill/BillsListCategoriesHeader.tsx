/** @format */

import { CATEGORIES } from "@sway/constants";
import { logDev } from "@sway/utils";
import React, { useCallback } from "react";
import { Form } from "react-bootstrap";
import Select, { MultiValue } from "react-select";
import { REACT_SELECT_STYLES } from "../../utils";

interface IProps {
    categories: string[];
    setCategories: React.Dispatch<React.SetStateAction<string[]>>;
}

const toSelecOption = (value: string) => ({ label: value, value });
const OPTIONS = CATEGORIES.map(toSelecOption);

const BillsListCategoriesHeader: React.FC<IProps> = ({ categories, setCategories }) => {
    const handleChangeCategory = useCallback(
        (values: MultiValue<{ label: string; value: string }>) => {
            logDev("BillsListCategoriesHeader.handleChange newValue -", values);
            if (!values) return;
            setCategories(values.map((v) => v.value));
        },
        [setCategories],
    );

    logDev("BillsListCategoriesHeader.categories -", categories);

    return (
        <Form.Group controlId="bill-categories" className="mt-2">
            <Select
                onChange={handleChangeCategory}
                value={categories.map(toSelecOption)}
                options={OPTIONS}
                isMulti
                isClearable
                closeMenuOnSelect={false}
                placeholder="Filter by category"
                styles={REACT_SELECT_STYLES}
            />
        </Form.Group>
    );
};

export default BillsListCategoriesHeader;
