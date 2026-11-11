interface IProps {
    className?: string;
    maxWidth?: number | string;
}

const SwayLogo: React.FC<IProps> = ({ className, maxWidth }) => {
    return (
        <img
            src={"/images/sway-us-light.png"}
            alt="Sway"
            className={className}
            style={{ maxWidth: maxWidth || 300, height: "auto" }}
        />
    );
};

export default SwayLogo;
