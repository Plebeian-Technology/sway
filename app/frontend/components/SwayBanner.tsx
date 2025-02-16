const SwayBanner = ({ className, maxWidth }: { className?: string; maxWidth?: number | string }) => {
    return (
        <img
            src={"/images/logo300.png"}
            alt="Sway"
            className={className}
            style={{ maxWidth: maxWidth || 100, height: "auto" }}
        />
    );
};

export default SwayBanner;
