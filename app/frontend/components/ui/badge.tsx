import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { Slot } from "radix-ui";

import { cn } from "@/lib/utils";

// @lat: [[badge-stamp-variant-design#Why stamp text uses the tone token, not a -foreground token]]
const badgeVariants = cva(
    "inline-flex items-center justify-center gap-1 whitespace-nowrap text-xs font-semibold [font-variant-numeric:tabular-nums_lining-nums] [&>svg]:pointer-events-none [&>svg]:size-3",
    {
        variants: {
            variant: {
                solid: "rounded-full border-neo border-border-strong px-2.5 py-0.5",
                // @lat: [[badge-stamp-variant-design#Why stamp text uses the tone token, not a -foreground token]]
                stamp: "rounded-lg border-0 px-2 py-1 tracking-widest uppercase ring-[length:var(--neo-border-width)] ring-inset",
                outline: "rounded-full border-neo border-border-strong bg-transparent px-2.5 py-0.5 text-foreground",
            },
            tone: {
                neutral: "",
                info: "",
                success: "",
                warning: "",
                danger: "",
                primary: "",
            },
        },
        compoundVariants: [
            // solid
            { variant: "solid", tone: "neutral", class: "bg-muted text-foreground" },
            { variant: "solid", tone: "info", class: "bg-info text-info-foreground" },
            {
                variant: "solid",
                tone: "success",
                class: "bg-success text-success-foreground",
            },
            {
                variant: "solid",
                tone: "warning",
                class: "bg-warning text-warning-foreground",
            },
            { variant: "solid", tone: "danger", class: "bg-destructive text-background" },
            { variant: "solid", tone: "primary", class: "bg-primary text-primary-foreground" },
            // stamp
            {
                variant: "stamp",
                tone: "neutral",
                class: "bg-muted/30 ring-border-strong text-foreground",
            },
            {
                variant: "stamp",
                tone: "info",
                class: "bg-info/12 ring-info text-info",
            },
            // @lat: [[badge-stamp-variant-design#Why stamp text uses the tone token, not a -foreground token]]
            {
                variant: "stamp",
                tone: "success",
                class: "bg-success/12 ring-success text-success",
            },
            {
                variant: "stamp",
                tone: "warning",
                class: "bg-warning/12 ring-warning text-warning",
            },
            {
                variant: "stamp",
                tone: "danger",
                class: "bg-destructive/12 ring-destructive text-destructive",
            },
            {
                variant: "stamp",
                tone: "primary",
                class: "bg-primary/12 ring-primary text-primary",
            },
        ],
        defaultVariants: {
            variant: "solid",
            tone: "neutral",
        },
    },
);

function Badge({
    className,
    variant,
    tone,
    asChild = false,
    ...props
}: React.ComponentProps<"span"> &
    VariantProps<typeof badgeVariants> & {
        asChild?: boolean;
    }) {
    const Comp = asChild ? Slot.Root : "span";

    return (
        <Comp
            data-slot="badge"
            data-variant={variant ?? "solid"}
            data-tone={tone ?? "neutral"}
            className={cn(badgeVariants({ variant, tone }), className)}
            {...props}
        />
    );
}

// oxlint-disable-next-line react-refresh/only-export-components -- badgeVariants is intentionally co-located with Badge (shadcn pattern); the Fast Refresh cost on a leaf primitive is acceptable.
export { Badge, badgeVariants };
