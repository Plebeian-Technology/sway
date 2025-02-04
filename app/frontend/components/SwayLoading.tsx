const SwayLoading = ({ isHidden, className }: { isHidden?: boolean; className?: string }) => (
    <img
        src="/images/loading.svg"
        alt="Loading..."
        className={className}
        style={{ maxWidth: "100%", visibility: isHidden ? "hidden" : "visible" }}
    />
);

export default SwayLoading;
