import { ROUTES } from "@sway/constants";
import { Link } from "react-router-dom";

const BillAvailableAfterVoting: React.FC = () => (
    <>
        <p className="text-center mt-1">Chart available after voting on bill(s).</p>
        <p className="text-center">
            Click <Link to={ROUTES.billOfTheWeek}>here</Link> to start voting!
        </p>
    </>
);

export default BillAvailableAfterVoting;
