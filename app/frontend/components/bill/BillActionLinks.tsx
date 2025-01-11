/** @format */

import { router } from "@inertiajs/react";
import { ROUTES } from "app/frontend/sway_constants";
import { Button } from "react-bootstrap";

const BillActionLinks: React.FC = () => {
    const handleNavigate = (pathname: string) => {
        router.visit(pathname);
    };

    return (
        <span>
            <Button as="span" variant="link" onClick={() => handleNavigate(ROUTES.legislators)}>
                See how you compare to your representatives
            </Button>
            &nbsp;<span>or</span>&nbsp;
            <Button as="span" variant="link" onClick={() => handleNavigate(ROUTES.pastBills)}>
                vote on past legislation.
            </Button>
        </span>
    );
};

export default BillActionLinks;
