export interface LocaleSelectOption {
    label: string;
    value: number | string;
}

// @lat: [[locale-picker-theme-styling#Why NEO_SELECT_CLASS is a class, not a component]]
export const NEO_SELECT_CLASS =
    "h-9 w-full min-w-0 max-w-full cursor-pointer rounded-xl border-neo border-border-strong bg-surface-3 px-3 text-sm font-semibold text-foreground ring-1 ring-inset ring-border-strong/70 transition-all hover:bg-accent hover:text-accent-foreground focus-visible:border-ring focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50";
