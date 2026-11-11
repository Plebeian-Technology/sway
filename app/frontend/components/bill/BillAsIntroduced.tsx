import React from "react";

import { hasLegalClause } from "app/frontend/components/bill/sway_utils/billTitle";

interface IProps {
    title: string;
}

// @lat: [[bill-as-introduced-title-split#Why the offline system spec's bill fixture avoids a dash in its title]]
const BillAsIntroduced: React.FC<IProps> = ({ title }) => {
    if (!hasLegalClause(title)) return null;

    return (
        <section className="rounded-xl border border-border bg-surface-2 px-4 py-4">
            <h2 className="text-xs font-black uppercase tracking-widest text-muted-foreground">As introduced</h2>
            {/* @lat: [[bill-as-introduced-title-split#Why the stored title uses whitespace-pre-line]] */}
            <p className="mt-2 whitespace-pre-line text-sm leading-6 text-muted-foreground">{title}</p>
        </section>
    );
};

export default BillAsIntroduced;
