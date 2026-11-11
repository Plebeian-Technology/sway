import * as React from "react";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "app/frontend/components/ui/accordion";

interface IProps {
    storageKey: string;
    title: React.ReactNode;
    children: React.ReactNode;
    defaultOpen?: boolean;
}

const VALUE_OPEN = "open";

// @lat: [[collapsible-panel#Storage that is not there falls back to the default]]
const readStoredOpen = (key: string, defaultOpen: boolean): boolean => {
    if (typeof window === "undefined") return defaultOpen;
    try {
        const v = window.localStorage.getItem(key);
        if (v === "1") return true;
        if (v === "0") return false;
        return defaultOpen;
    } catch {
        return defaultOpen;
    }
};

// @lat: [[collapsible-panel#Storage that is not there falls back to the default]]
const writeStoredOpen = (key: string, open: boolean): void => {
    if (typeof window === "undefined") return;
    try {
        window.localStorage.setItem(key, open ? "1" : "0");
    } catch {
        return;
    }
};

// @lat: [[collapsible-panel#No effect watches the stored value]]
const CollapsiblePanel: React.FC<IProps> = ({ storageKey, title, children, defaultOpen = true }) => {
    const [open, setOpen] = React.useState<boolean>(() => readStoredOpen(storageKey, defaultOpen));

    const handleValueChange = (value: string) => {
        const next = value === VALUE_OPEN;
        setOpen(next);
        writeStoredOpen(storageKey, next);
    };

    return (
        <Accordion
            type="single"
            collapsible
            value={open ? VALUE_OPEN : ""}
            onValueChange={handleValueChange}
            data-testid={`collapsible-panel-${storageKey}`}
        >
            <AccordionItem value={VALUE_OPEN}>
                <AccordionTrigger data-testid={`collapsible-panel-trigger-${storageKey}`}>{title}</AccordionTrigger>
                <AccordionContent data-testid={`collapsible-panel-content-${storageKey}`}>{children}</AccordionContent>
            </AccordionItem>
        </Accordion>
    );
};

export default CollapsiblePanel;
