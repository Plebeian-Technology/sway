import * as React from "react";

import { cn } from "@/lib/utils";

// @lat: [[theme-tokens#Why density and motion belong to the theme]]
function Input({ className, type, ...props }: React.ComponentProps<"input">) {
    return (
        <input
            type={type}
            data-slot="input"
            className={cn(
                "h-(--control-height) w-full min-w-0 rounded-xl border-neo border-border-strong bg-input px-(--control-pad-x) py-2 text-base shadow-neo transition-[color,box-shadow,transform] outline-none selection:bg-primary selection:text-primary-foreground file:inline-flex file:h-7 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 md:text-sm",
                "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
                "aria-invalid:border-destructive aria-invalid:ring-destructive/20",
                className,
            )}
            {...props}
        />
    );
}

export { Input };
