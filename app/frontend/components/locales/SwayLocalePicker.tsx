import { cn } from "@/lib/utils";

import { NEO_SELECT_CLASS, type LocaleSelectOption } from "app/frontend/components/ui/LocaleSelect";
import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";
import type { ThemeId } from "app/frontend/styles/themes";

interface IProps {
    id: string;
    options: LocaleSelectOption[];
    value: number | string | undefined;
    onChange: (id: number) => void;
    className?: string;
}

// @lat: [[theme-tokens#Theme tokens#Why native select chrome is defined once, globally]]
const THEME_SELECT_CLASSES: Partial<Record<ThemeId, string>> = {
    ballot: "ball-select",
    banner: "bnl-select",
    cornerstore: "csl-select",
    monochrome: "monochrome-select",
    "service-manual": "service-manual-select",
    "swiss-grid": "swiss-grid-select",
};

const SwayLocalePicker: React.FC<IProps> = ({ id, options, value, onChange, className }) => {
    const themeId = useActiveThemeId();

    return (
        <select
            id={id}
            value={value}
            onChange={(event) => onChange(Number(event.target.value))}
            className={cn(THEME_SELECT_CLASSES[themeId] ?? NEO_SELECT_CLASS, className)}
        >
            {options.map((option) => (
                <option key={option.value} value={option.value}>
                    {option.label}
                </option>
            ))}
        </select>
    );
};

export default SwayLocalePicker;
