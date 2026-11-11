import React from "react";

import { splitBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";

interface IProps {
    title: string;
    qualifierClassName?: string;
}

// @lat: [[bill-entry-title-category-qualifier-split#What billEntryTitle.test.tsx checks beyond presence]]
const BillEntryTitle: React.FC<IProps> = ({ title, qualifierClassName }) => {
    const { headline, deck } = splitBillTitle(title);

    if (!deck) return <>{headline}</>;

    return (
        <>
            {headline}
            <span className={qualifierClassName}>{` — ${deck}`}</span>
        </>
    );
};

export default BillEntryTitle;
