"use client";

import * as React from "react";
import { Tabs as TabsPrimitive } from "radix-ui";

import { cn } from "@/lib/utils";

// @lat: [[badge-stamp-variant-design#ui/Tabs: Broadside tabs per the 27.3 UI spec]]

function Tabs({ className, ...props }: React.ComponentProps<typeof TabsPrimitive.Root>) {
    return <TabsPrimitive.Root data-slot="tabs" className={cn("flex flex-col gap-4", className)} {...props} />;
}

function TabsList({ className, ...props }: React.ComponentProps<typeof TabsPrimitive.List>) {
    return (
        <TabsPrimitive.List
            data-slot="tabs-list"
            className={cn(
                // @lat: [[tab-strips-at-narrow-viewports#Why the strips wrap rather than scroll]]
                "relative flex w-full flex-wrap items-stretch gap-0 border-b-neo border-border-soft text-foreground",
                // vertical rules between triggers via right border on each trigger except the last
                "[&>button]:border-r-neo [&>button]:border-border-soft [&>button:last-child]:border-r-0",
                className,
            )}
            {...props}
        />
    );
}

function TabsTrigger({ className, ...props }: React.ComponentProps<typeof TabsPrimitive.Trigger>) {
    return (
        <TabsPrimitive.Trigger
            data-slot="tabs-trigger"
            className={cn(
                "relative inline-flex shrink-0 cursor-pointer items-center justify-center gap-2 px-4 py-2.5 text-sm font-semibold tracking-wide uppercase whitespace-nowrap text-muted-foreground transition-colors outline-none",
                "hover:text-foreground",
                "focus-visible:ring-2 focus-visible:ring-ring/50",
                "disabled:pointer-events-none disabled:opacity-50",
                // active: 3px ink underline flush to bottom rule + 8% accent wash
                "data-[state=active]:text-foreground data-[state=active]:bg-accent/8",
                "data-[state=active]:after:absolute data-[state=active]:after:right-0 data-[state=active]:after:bottom-[calc(-1*var(--neo-border-width))] data-[state=active]:after:left-0 data-[state=active]:after:h-[3px] data-[state=active]:after:bg-foreground data-[state=active]:after:content-['']",
                "[&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
                className,
            )}
            {...props}
        />
    );
}

function TabsContent({ className, ...props }: React.ComponentProps<typeof TabsPrimitive.Content>) {
    return (
        <TabsPrimitive.Content
            data-slot="tabs-content"
            className={cn(
                "flex-1 outline-none",
                "data-[state=inactive]:hidden",
                "motion-safe:data-[state=active]:animate-in motion-safe:data-[state=active]:fade-in-0 motion-safe:data-[state=active]:slide-in-from-bottom-1 motion-safe:data-[state=active]:duration-slow",
                className,
            )}
            {...props}
        />
    );
}

export { Tabs, TabsList, TabsTrigger, TabsContent };
