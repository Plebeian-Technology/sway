import { Monitor, Moon, Sun, type LucideIcon } from "lucide-react";

import { Button } from "app/frontend/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { useTheme, type ThemeMode } from "app/frontend/hooks/useTheme";
import { cn } from "app/frontend/lib/utils";

// @lat: [[drawer-header-and-nav-selection#Why ThemeToggle omits aria-pressed and shares the mobile cycle order]]
const CYCLE: ThemeMode[] = ["light", "system", "dark"];
const ICONS: Record<ThemeMode, LucideIcon> = { light: Sun, system: Monitor, dark: Moon };
const LABELS: Record<ThemeMode, string> = { light: "Light", system: "Auto", dark: "Dark" };

const nextOf = (current: ThemeMode): ThemeMode => CYCLE[(CYCLE.indexOf(current) + 1) % CYCLE.length];

interface IProps {
    className?: string;
}

const ThemeToggle: React.FC<IProps> = ({ className }) => {
    const { preference, setPreference } = useTheme();
    const next = nextOf(preference);
    const Icon = ICONS[preference];

    return (
        <TooltipProvider delayDuration={200}>
            <Tooltip>
                <TooltipTrigger asChild>
                    <Button
                        type="button"
                        size="sm"
                        variant="secondary"
                        // @lat: [[drawer-header-and-nav-selection#Why ThemeToggle omits aria-pressed and shares the mobile cycle order]]
                        aria-label={`Theme: ${LABELS[preference]}. Click for ${LABELS[next]}.`}
                        className={cn("min-w-0 justify-between px-3", className)}
                        onClick={() => setPreference(next)}
                    >
                        <span className="inline-flex min-w-0 items-center gap-2">
                            <Icon className="size-4" aria-hidden="true" />
                            <span className="truncate">{LABELS[preference]}</span>
                        </span>
                    </Button>
                </TooltipTrigger>
                <TooltipContent side="top">{`Switch to ${LABELS[next]} mode`}</TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
};

export default ThemeToggle;
