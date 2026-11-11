import { router, usePage } from "@inertiajs/react";
import { useCallback, useRef } from "react";

import { getDistrictLegislatorNames } from "app/frontend/sway_utils";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { cn } from "app/frontend/lib/utils";
import { sway } from "sway";

interface IProps {
    district?: sway.IDistrict;
    label: string;
    className?: string;
}

interface IPageProps {
    legislators?: sway.ILegislator[];
    [key: string]: unknown;
}

const DistrictLabel: React.FC<IProps> = ({ district, label, className }) => {
    const page = usePage<IPageProps>();
    const legislators = page.props.legislators;
    const requested = useRef(false);

    // @lat: [[district-chart-tooltip#The roster is fetched when a reader asks for it]]
    const requestLegislators = useCallback(() => {
        if (requested.current || legislators !== undefined) return;

        requested.current = true;
        router.reload({ only: ["legislators"] });
    }, [legislators]);

    const names = getDistrictLegislatorNames(district, legislators);

    if (legislators !== undefined && names.length === 0) {
        return <span className={cn("truncate", className)}>{label}</span>;
    }

    const prefix = names.length === 1 ? "Representative" : "Representatives";

    return (
        <TooltipProvider delayDuration={150}>
            <Tooltip>
                <TooltipTrigger asChild>
                    <span
                        className={cn(
                            "block cursor-help truncate underline decoration-dotted underline-offset-3",
                            className,
                        )}
                        onPointerEnter={requestLegislators}
                        onFocus={requestLegislators}
                    >
                        {label}
                    </span>
                </TooltipTrigger>
                <TooltipContent side="top">
                    {names.length === 0 ? (
                        <span className="text-muted-foreground">Looking up representatives…</span>
                    ) : (
                        <>
                            <span className="font-semibold">{prefix}:</span> {names.join(", ")}
                        </>
                    )}
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
};

export default DistrictLabel;
