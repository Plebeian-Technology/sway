/** @format */

import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps extends sway.IPlainObject {
    src: string;
    alt?: string;
    style?: React.CSSProperties;
    containerStyle?: React.CSSProperties;
    handleClick?: (e: React.MouseEvent<HTMLElement>) => void;
}

const SwaySvg: React.FC<IProps> = ({ src, alt, style, handleClick }) => {
    return <Image src={src} alt={alt ? alt : "icon"} style={style} onClick={handleClick} />;
};

interface IIconProps {
    src: string;
    alt?: string;
    style?: React.CSSProperties;
    handleClick?: (e: React.MouseEvent<HTMLElement>) => void;
}

export const SwaySvgIcon: React.FC<IIconProps> = ({ src, alt, handleClick, style }) => {
    return <Image src={src} alt={alt} style={style} onClick={handleClick} />;
};

export default SwaySvg;
