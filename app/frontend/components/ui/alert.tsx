import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const alertVariants = cva(
    "relative grid w-full grid-cols-[0_1fr] items-start gap-y-1 rounded-xl border-neo bg-card px-4 py-3 text-sm shadow-neo has-[>svg]:grid-cols-[calc(var(--spacing)*4)_1fr] has-[>svg]:gap-x-3 [&>svg]:size-4 [&>svg]:translate-y-0.5 [&>svg]:text-current",
    {
        variants: {
            variant: {
                default: "border-border-strong text-foreground",
                info: "border-info bg-info/12 text-foreground",
                success: "border-success bg-success/12 text-foreground",
                warning: "border-warning bg-warning/12 text-foreground",
                destructive: "border-destructive bg-destructive/12 text-destructive [&>svg]:text-destructive",
            },
        },
        defaultVariants: {
            variant: "default",
        },
    },
);

function Alert({ className, variant, ...props }: React.ComponentProps<"div"> & VariantProps<typeof alertVariants>) {
    return (
        <div
            data-slot="alert"
            data-variant={variant ?? "default"}
            role="alert"
            className={cn(alertVariants({ variant }), className)}
            {...props}
        />
    );
}

function AlertTitle({ className, ...props }: React.ComponentProps<"div">) {
    return (
        <div
            data-slot="alert-title"
            className={cn("col-start-2 min-h-4 font-semibold tracking-tight line-clamp-1", className)}
            {...props}
        />
    );
}

function AlertDescription({ className, ...props }: React.ComponentProps<"div">) {
    return (
        <div
            data-slot="alert-description"
            className={cn(
                "col-start-2 grid justify-items-start gap-1 text-sm text-muted-foreground [&_p]:leading-relaxed",
                className,
            )}
            {...props}
        />
    );
}

// oxlint-disable-next-line react-refresh/only-export-components -- alertVariants is intentionally co-located with Alert (shadcn pattern); the Fast Refresh cost on a leaf primitive is acceptable.
export { Alert, AlertTitle, AlertDescription, alertVariants };
