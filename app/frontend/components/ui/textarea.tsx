import * as React from "react";

import { cn } from "@/lib/utils";

function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
    return (
        <textarea
            data-slot="textarea"
            className={cn(
                "flex min-h-24 w-full rounded-xl border-neo border-border-strong bg-input px-3 py-2 text-base shadow-neo transition-[color,box-shadow] outline-none",
                "placeholder:text-muted-foreground selection:bg-primary selection:text-primary-foreground",
                "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
                "aria-invalid:border-destructive aria-invalid:ring-destructive/20",
                "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50",
                "md:text-sm",
                className,
            )}
            {...props}
        />
    );
}

export { Textarea };
