/** @format */

interface IProps {
    children: React.ReactNode;
    style?: React.CSSProperties;
}

const SwayBase: React.FC<IProps> = (props) => {
    return <div style={props.style && props.style}>{props.children}</div>;
};

export default SwayBase;
