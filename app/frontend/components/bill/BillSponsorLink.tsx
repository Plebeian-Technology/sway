import { Link } from "@inertiajs/react";

import { PREFETCH_CACHE_FOR, ROUTES } from "app/frontend/sway_constants";

interface IProps {
    legislatorId: string | number;
    className?: string;
    children: React.ReactNode;
}

// @lat: [[hover-prefetch-links#Links that warm before the click#Why the sponsor link is one component]]
const BillSponsorLink: React.FC<IProps> = ({ legislatorId, className, children }) => {
    return (
        <Link
            href={ROUTES.legislator(legislatorId)}
            className={className}
            prefetch="hover"
            cacheFor={PREFETCH_CACHE_FOR}
            viewTransition
        >
            {children}
        </Link>
    );
};

export default BillSponsorLink;
