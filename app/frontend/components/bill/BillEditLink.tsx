import { Link } from "@inertiajs/react";
import { Pencil } from "lucide-react";

import { useUser } from "app/frontend/hooks/users/useUser";
import { cn } from "app/frontend/lib/utils";
import { ROUTES } from "app/frontend/sway_constants";

interface IProps {
    billId: number;
    // @lat: [[bills-controller-design#Why BillEditLink's visibility is proven from the prop, not the markup]]
    billIdentifier: string;
    variant?: "row" | "detail";
    isArchived?: boolean;
    className?: string;
}

// @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]]
const BillEditLink: React.FC<IProps> = ({ billId, billIdentifier, variant = "row", isArchived = false, className }) => {
    const user = useUser();
    const isSwayAdmin = !!user?.is_admin;

    if (!isSwayAdmin || isArchived) return null;

    const link = (
        <Link
            href={ROUTES.billCreatorTab(billId)}
            viewTransition
            aria-label={variant === "row" ? `Edit bill ${billIdentifier}` : undefined}
            className={cn(
                "inline-flex shrink-0 items-center justify-center gap-1.5 rounded-md border-neo border-border bg-card text-muted-foreground shadow-neo hover:bg-surface-2 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50",
                variant === "row" ? "size-11" : "h-11 px-4 text-sm font-semibold",
                className,
            )}
        >
            <Pencil className="size-4" aria-hidden="true" />
            {variant === "detail" && <span>Edit bill</span>}
        </Link>
    );

    if (variant === "row") return link;

    return <div className="flex justify-end pb-2">{link}</div>;
};

export default BillEditLink;
