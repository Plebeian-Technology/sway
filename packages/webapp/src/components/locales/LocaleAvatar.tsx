import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    locale: sway.ILocale;
    maxWidth?: number;
}

const LocaleAvatar: React.FC<IProps> = (props) => {
    const maxWidth = props.maxWidth || 100;

    return (
        <Image
            src={`/avatars/${props.locale.name}.svg`}
            className="rounded mx-auto text-center"
            style={{
                maxWidth,
            }}
        />
    );
};

export default LocaleAvatar;
