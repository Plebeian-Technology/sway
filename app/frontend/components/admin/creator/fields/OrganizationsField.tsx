import BillCreatorOrganizations from "app/frontend/components/admin/creator/BillCreatorOrganizations";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";

const OrganizationsField = <T,>({ swayField }: IFieldProps<T>) => {
    const { errors } = useFormContext<T>();

    return (
        <div key={swayField.name} className="col-12 py-4">
            <BillCreatorOrganizations error={(errors as Record<string, any>)[swayField.name] as string | undefined} />
        </div>
    );
};

export default OrganizationsField;
