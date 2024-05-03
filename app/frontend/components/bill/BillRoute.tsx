import { useParams } from "react-router-dom";
import Bill from "../../pages/Bill";

const BillRoute: React.FC = () => {
    const { billFirestoreId } = useParams() as { billFirestoreId: string };
    return <Bill billFirestoreId={billFirestoreId} />;
};

export default BillRoute;
