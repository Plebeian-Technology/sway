"use client";

import * as React from "react";
import { Progress as ProgressPrimitive } from "radix-ui";

import { cn } from "@/lib/utils";

function Progress({ className, value, ...props }: React.ComponentProps<typeof ProgressPrimitive.Root>) {
    const clamped = typeof value === "number" ? Math.max(0, Math.min(100, value)) : 0;
    return (
        <ProgressPrimitive.Root
            data-slot="progress"
            value={value}
            className={cn(
                "relative h-3 w-full overflow-hidden rounded-full border-neo border-border-strong bg-muted shadow-neo",
                className,
            )}
            {...props}
        >
            <ProgressPrimitive.Indicator
                data-slot="progress-indicator"
                className="h-full w-full flex-1 bg-primary transition-transform duration-normal"
                style={{ transform: `translateX(-${100 - clamped}%)` }}
            />
        </ProgressPrimitive.Root>
    );
}

export { Progress };
