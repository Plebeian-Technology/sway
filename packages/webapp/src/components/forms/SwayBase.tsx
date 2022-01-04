/** @format */
import { sway } from "sway";

interface IProps {
    children: React.ReactNode;
    style?: sway.IPlainObject;
}

const SwayBase: React.FC<IProps> = (props) => {
    return <div style={props.style && props.style}>{props.children}</div>;
};

export default SwayBase;
