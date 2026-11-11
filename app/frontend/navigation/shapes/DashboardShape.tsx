const DashboardShape: React.FC = () => (
    <div className="flex flex-col gap-6">
        <div className="placeholder-block h-10 w-1/3" aria-hidden="true" />
        <div className="grid grid-cols-2 gap-4 md:grid-cols-3">
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
        </div>
    </div>
);

export default DashboardShape;
