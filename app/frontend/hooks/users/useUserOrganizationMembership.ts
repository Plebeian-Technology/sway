import { usePage } from "@inertiajs/react";
import { sway } from "sway";

export interface IPositionWithBill extends sway.IOrganizationPosition {
    bill: sway.IBill;
    locked?: boolean;
}

export interface IOrganizationMember {
    id: number;
    full_name: string;
    email: string;
    role: "admin" | "standard";
}

interface IPendingChange {
    id: number;
    created_at: string;
    organization_bill_position_id: number;
    approved_by_id: number | null;
    rejected_by_id?: number | null;
    rejected_at?: string | null;
    // @lat: [[pending-change-card-frontend-design#Why IPendingChange.status is optional]]
    status?: "pending" | "approved" | "rejected";
    updated_by_id: number;
    new_summary: string;
    new_support: string;
    previous_summary: string;
    previous_support: string;
}

export type IMembership = sway.IOrganizationMembership & {
    organization: sway.IOrganization;
    members?: IOrganizationMember[];
    positions?: IPositionWithBill[];
    pending_changes: IPendingChange[];
    role?: "admin" | "standard";
};

export const useUserOrganizationMembership = (): IMembership | undefined => {
    return usePage<{ membership?: IMembership; [key: string]: unknown }>().props.membership;
};
