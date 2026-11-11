import { Link } from "@inertiajs/react";

import { PREFETCH_CACHE_FOR, ROUTES } from "app/frontend/sway_constants";

interface IProps {
    billId: string | number;
    className?: string;
    children: React.ReactNode;
}

// @lat: [[navigation-placeholder-tracer#Why bill-row links route through one BillRowLink component]]
// @lat: [[hover-prefetch-links#Links that warm before the click#Which links warm on hover and which on mousedown]]
const BillRowLink: React.FC<IProps> = ({ billId, className, children }) => {
    return (
        <Link
            href={ROUTES.bill(billId)}
            className={className}
            prefetch="click"
            cacheFor={PREFETCH_CACHE_FOR}
            viewTransition
        >
            {children}
        </Link>
    );
};

export default BillRowLink;
