import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { useTheme } from "app/frontend/hooks/useTheme";
import { isValidThemeId, THEMES } from "app/frontend/styles/themes";

interface IProps {
    className?: string;
}

const ThemePicker: React.FC<IProps> = ({ className }) => {
    const { themeId, setThemeId } = useTheme();

    const options = THEMES.filter((theme) => !theme.hidden || theme.id === themeId);

    return (
        <Select
            value={themeId}
            onValueChange={(value) => {
                if (isValidThemeId(value)) {
                    setThemeId(value);
                }
            }}
        >
            <SelectTrigger size="sm" className={className} aria-label="Theme">
                <SelectValue />
            </SelectTrigger>
            <SelectContent>
                {options.map((theme) => (
                    <SelectItem key={theme.id} value={theme.id}>
                        {theme.label}
                    </SelectItem>
                ))}
            </SelectContent>
        </Select>
    );
};

export default ThemePicker;
