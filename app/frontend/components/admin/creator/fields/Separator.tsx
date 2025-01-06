import { IFieldProps } from "app/frontend/components/admin/creator/types";
import SwayLogo from "app/frontend/components/SwayLogo";

const Separator = <T,>({ swayField }: IFieldProps<T>) => {
    return (
        <div key={swayField.name} className="text-center my-5">
            <SwayLogo />
        </div>
    );
};

export default Separator;
