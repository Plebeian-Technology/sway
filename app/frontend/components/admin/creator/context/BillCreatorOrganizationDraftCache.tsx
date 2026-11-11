import { useState } from "react";
import { TOrganizationOption } from "app/frontend/components/admin/creator/types";
import { BillCreatorOrganizationDraftCacheContext } from "app/frontend/components/admin/creator/context/BillCreatorOrganizationDraftCacheContext";

interface IProps {
    children: React.ReactNode;
}

// @lat: [[bill-creator-organization-form#The cache outlives the organization-set form]]
const BillCreatorOrganizationDraftCache: React.FC<IProps> = ({ children }) => {
    const [cache] = useState(() => new Map<number | string, TOrganizationOption>());

    return (
        <BillCreatorOrganizationDraftCacheContext.Provider value={cache}>
            {children}
        </BillCreatorOrganizationDraftCacheContext.Provider>
    );
};

export default BillCreatorOrganizationDraftCache;
