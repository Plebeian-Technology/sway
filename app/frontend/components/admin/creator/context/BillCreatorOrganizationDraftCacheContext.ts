import { createContext } from "react";
import { TOrganizationOption } from "app/frontend/components/admin/creator/types";

export const BillCreatorOrganizationDraftCacheContext = createContext<Map<number | string, TOrganizationOption> | null>(
    null,
);
