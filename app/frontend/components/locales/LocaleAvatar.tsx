import { Image, ImageProps } from "react-bootstrap";
import { useLocale } from "../../hooks/useLocales";

interface IProps extends ImageProps {
    maxWidth?: number;
}

const LocaleAvatar: React.FC<IProps> = ({ maxWidth, ...props }) => {
    const [locale] = useLocale();
    if (!locale) {
        return null;
    }
    return (
        <Image
            {...props}
            src={`/images/flags/${locale.name}.svg`}
            className="rounded mx-auto text-center"
            style={{
                maxWidth: maxWidth || 100,
            }}
        />
    );
};

export default LocaleAvatar;
