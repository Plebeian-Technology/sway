import { useParams } from "react-router-dom";
import Bill from "../../pages/Bill";

const BillRoute: React.FC = () => {
    const { billExternalId } = useParams() as { billExternalId: string };
    return <Bill billExternalId={billExternalId} />;
};

export default BillRoute;
