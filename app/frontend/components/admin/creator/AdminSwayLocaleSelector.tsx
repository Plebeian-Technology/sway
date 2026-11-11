import { useAdminSwayLocaleOptions, useSwayLocale } from "app/frontend/hooks/useSwayLocales";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";

interface IProps {
    onSwayLocaleChange: (swayLocaleId: number) => void;
    // @lat: [[bill-creator-shell#Why confirmNav forwards pendingSwayLocaleId explicitly]]
    pendingSwayLocaleId?: number;
}

// @lat: [[bill-interesting-score#Why locale selection stays in the shell]]
const AdminSwayLocaleSelector: React.FC<IProps> = ({ onSwayLocaleChange, pendingSwayLocaleId }) => {
    const options = useAdminSwayLocaleOptions();
    const [swayLocale] = useSwayLocale();
    const shownSwayLocaleId = pendingSwayLocaleId ?? swayLocale?.id;

    return (
        <div className="flex items-center gap-1.5">
            <Select
                value={shownSwayLocaleId !== undefined ? String(shownSwayLocaleId) : undefined}
                onValueChange={(next) => onSwayLocaleChange(Number(next))}
            >
                <SelectTrigger
                    data-testid="admin-locale-selector"
                    aria-label="Locale"
                    size="sm"
                    className="min-h-11 w-auto bg-muted text-xs md:min-h-0"
                >
                    <SelectValue placeholder="Sway Locale" />
                </SelectTrigger>
                <SelectContent>
                    {options.map((o, i) => (
                        <SelectItem key={`${o.value}-${i}`} value={String(o.value)} className="min-h-11 md:min-h-0">
                            {o.label}
                        </SelectItem>
                    ))}
                </SelectContent>
            </Select>
            <FeatureInfo note="creator.localeSelector" />
        </div>
    );
};

export default AdminSwayLocaleSelector;
