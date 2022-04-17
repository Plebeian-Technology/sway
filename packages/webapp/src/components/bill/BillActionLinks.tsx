/** @format */

import { ROUTES } from "@sway/constants";
import { useNavigate } from "react-router-dom";

const BillActionLinks: React.FC = () => {
    const navigate = useNavigate();

    const handleNavigate = (pathname: string) => {
        navigate({ pathname });
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
