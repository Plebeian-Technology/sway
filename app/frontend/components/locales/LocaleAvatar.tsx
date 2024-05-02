import { Image } from "react-bootstrap";
import { useLocale } from "../../hooks/useLocales";

interface IProps {
    maxWidth?: number;
}

const LocaleAvatar: React.FC<IProps> = ({ maxWidth }) => {
    const [locale] = useLocale();
    if (!locale) {
        return null;
    }
    return (
        <Image
            src={`/assets/avatars/${locale.name}.svg`}
            className="rounded mx-auto text-center"
            style={{
                maxWidth: maxWidth || 100,
            }}
        />
    );
};

export default LocaleAvatar;
