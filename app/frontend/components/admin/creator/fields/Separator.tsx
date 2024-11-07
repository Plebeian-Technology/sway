import { IFieldProps } from "app/frontend/components/admin/creator/types";
import SwayLogo from "app/frontend/components/SwayLogo";

const Separator: React.FC<IFieldProps> = ({ swayField }) => {
    return (
        <div key={swayField.name} className="text-center my-5">
            <SwayLogo />
        </div>
    );
};

export default Separator;
