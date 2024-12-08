import { router } from "@inertiajs/react";
import {
    IApiBillCreator,
    ICreatorLegislatorVotes,
    ICreatorOrganizations,
} from "app/frontend/components/admin/creator/types";

import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";
import { ROUTES } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { Button } from "react-bootstrap";
import { FiSave } from "react-icons/fi";
import { UseInertiaFormProps } from "use-inertia-form";

interface IProps {
    form:
        | UseInertiaFormProps<IApiBillCreator>
        | UseInertiaFormProps<ICreatorOrganizations>
        | UseInertiaFormProps<ICreatorLegislatorVotes>;
    storage: TempBillStorage;
    blurredFieldName?: string;
}

const BillCreatorFormHeader: React.FC<IProps> = ({ form, storage, blurredFieldName }) => {
    const params = useSearchParams();

    return (
        <div className="row align-items-center my-2">
            <div className="col ">
                <span className={blurredFieldName ? "visible" : "invisible"}>
                    Store Temporary {storage.name()} field: <b>{blurredFieldName ? titleize(blurredFieldName) : ""}</b>
                </span>
            </div>
            <div className="col text-center">
                <Button disabled={form.processing} variant="primary" type="submit">
                    <FiSave />
                    &nbsp;Save
                </Button>
            </div>
            <div className="col text-end">
                <Button
                    variant="outline-secondary"
                    onClick={() => {
                        storage.remove();
                        form.reset();
                        router.get(`${ROUTES.billOfTheWeekCreator}?${params.qs}`);
                    }}
                >
                    Don't Save + Reset to New
                </Button>
            </div>
        </div>
    );
};

export default BillCreatorFormHeader;
