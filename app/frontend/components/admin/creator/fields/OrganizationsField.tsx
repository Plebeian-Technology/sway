import BillCreatorOrganizations from "app/frontend/components/admin/BillCreatorOrganizations";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { useFormikContext } from "formik";
import { useCallback } from "react";

const OrganizationsField: React.FC<IFieldProps> = ({ swayField }) => {
    const { errors, touched, setTouched } = useFormikContext();

    const handleSetTouched = useCallback(
        (fieldname: string) => {
            if ((touched as Record<string, any>)[fieldname]) return;
            setTouched({
                ...touched,
                [fieldname]: true,
            }).catch(console.error);
        },
        [setTouched, touched],
    );

    return (
        <div key={swayField.name} className="col-12 py-4">
            <BillCreatorOrganizations
                swayFieldName={swayField.name}
                error={(errors as Record<string, any>)[swayField.name] as string | undefined}
                handleSetTouched={handleSetTouched}
            />
        </div>
    );
};

export default OrganizationsField;
