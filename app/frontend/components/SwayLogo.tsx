const SwayLogo = ({ className, maxWidth }: { className?: string; maxWidth?: number }) => {
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
