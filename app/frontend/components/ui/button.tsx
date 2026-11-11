import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { Slot } from "radix-ui";

import { cn } from "@/lib/utils";

// @lat: [[theme-tokens#Why density and motion belong to the theme]]
const buttonVariants = cva(
    "inline-flex shrink-0 cursor-pointer items-center justify-center gap-2 whitespace-nowrap rounded-xl border-neo border-border-strong text-sm font-semibold outline-none ring-1 ring-inset ring-border-strong/70 transition-all focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-destructive/20 shadow-neo active:translate-x-0 active:translate-y-0 active:shadow-none [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
    {
        variants: {
            variant: {
                default: "bg-primary text-primary-foreground hover:bg-primary/95",
                destructive: "bg-destructive text-background hover:bg-destructive/90 focus-visible:ring-destructive/20",
                outline: "bg-surface-3 text-foreground hover:bg-accent hover:text-accent-foreground",
                secondary: "bg-surface-2 text-secondary-foreground hover:bg-accent hover:text-accent-foreground",
                ghost: "border-transparent bg-transparent shadow-none hover:bg-accent hover:text-accent-foreground",
                link: "text-primary underline-offset-4 hover:underline",
            },
            size: {
                default: "h-(--control-height) px-(--control-pad-x) py-2 has-[>svg]:px-3",
                xs: "h-6 gap-1 rounded-md px-2 text-xs has-[>svg]:px-1.5 [&_svg:not([class*='size-'])]:size-3",
                sm: "h-11 gap-1.5 rounded-md px-3 has-[>svg]:px-2.5 sm:h-8",
                lg: "h-11 rounded-md px-6 has-[>svg]:px-4 sm:h-10",
                icon: "size-11 sm:size-9",
                "icon-xs": "size-6 rounded-md [&_svg:not([class*='size-'])]:size-3",
                "icon-sm": "size-11 sm:size-8",
                "icon-lg": "size-11 sm:size-10",
            },
        },
        defaultVariants: {
            variant: "default",
            size: "default",
        },
    },
);

function Button({
    className,
    variant = "default",
    size = "default",
    asChild = false,
    ...props
}: React.ComponentProps<"button"> &
    VariantProps<typeof buttonVariants> & {
        asChild?: boolean;
    }) {
    const Comp = asChild ? Slot.Root : "button";

    return (
        <Comp
            data-slot="button"
            data-variant={variant}
            data-size={size}
            className={cn(buttonVariants({ variant, size, className }))}
            {...props}
        />
    );
}

// oxlint-disable-next-line react-refresh/only-export-components -- buttonVariants is intentionally co-located with Button (shadcn pattern); the Fast Refresh cost on a leaf primitive is acceptable.
export { Button, buttonVariants };
