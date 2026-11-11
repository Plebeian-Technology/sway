"use client";

import * as React from "react";
import { Switch as SwitchPrimitive } from "radix-ui";

import { cn } from "@/lib/utils";

function Switch({ className, ...props }: React.ComponentProps<typeof SwitchPrimitive.Root>) {
    return (
        <SwitchPrimitive.Root
            data-slot="switch"
            className={cn(
                "peer inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border-neo border-border-strong bg-muted shadow-neo transition-colors duration-normal outline-none",
                "focus-visible:ring-2 focus-visible:ring-ring/50 focus-visible:ring-offset-2 focus-visible:ring-offset-background",
                "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50",
                "data-[state=checked]:bg-primary",
                className,
            )}
            {...props}
        >
            <SwitchPrimitive.Thumb
                data-slot="switch-thumb"
                className={cn(
                    "pointer-events-none block size-4 translate-x-0.5 rounded-full border-neo border-border-strong bg-card ring-0 transition-transform duration-normal",
                    // Offset = track(2.75rem) - thumb(1rem) - 2*border - 0.125rem trailing gap.
                    // Derived from tokens so calm intensity (1px border) stays flush.
                    "data-[state=checked]:translate-x-[calc(2.75rem-1rem-(var(--neo-border-width)*2)-0.125rem)]",
                )}
            />
        </SwitchPrimitive.Root>
    );
}

export { Switch };
