/** @format */

import { router } from "@inertiajs/react";
import { ROUTES } from "app/frontend/sway_constants";

const BillActionLinks: React.FC = () => {

    const handleNavigate = (pathname: string) => {
        router.visit(pathname);
    };

    return (
        <span>
            <span className={"link"} onClick={() => handleNavigate(ROUTES.legislators)}>
                See how you compare to your representatives
            </span>
            &nbsp;<span>or</span>&nbsp;
            <span className={"link"} onClick={() => handleNavigate(ROUTES.pastBills)}>
                vote on past legislation.
            </span>
        </span>
    );
};

export default BillActionLinks;
