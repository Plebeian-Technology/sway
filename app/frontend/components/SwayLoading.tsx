const SwayLoading = ({ isHidden, className }: { isHidden?: boolean; className?: string }) => (
    <img
        src="/images/loading.svg"
        alt="Loading..."
        className={className}
        style={{ width: "100%", maxWidth: "100px", visibility: isHidden ? "hidden" : "visible" }}
    />
);

export default SwayLoading;
