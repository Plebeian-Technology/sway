const SwayLoading = ({ isHidden = true, className }: { isHidden?: boolean; className?: string }) => (
    <div
        className={`container text-center ${className || ""}`}
        style={{
            visibility: isHidden ? "hidden" : "visible",
        }}
    >
        <img src="/images/loading.svg" alt="Loading..." style={{ maxWidth: 100 }} />
    </div>
);

export default SwayLoading;
