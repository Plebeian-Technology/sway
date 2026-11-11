const DetailShape: React.FC = () => (
    <div className="flex flex-col gap-6">
        <div className="placeholder-block h-10 w-3/4" aria-hidden="true" />
        <div className="flex gap-4">
            <div className="placeholder-block h-4 w-32" aria-hidden="true" />
            <div className="placeholder-block h-4 w-24" aria-hidden="true" />
        </div>
        <div className="placeholder-block h-40 w-full" aria-hidden="true" />
        <div className="flex flex-col gap-2">
            <div className="placeholder-block h-4 w-full" aria-hidden="true" />
            <div className="placeholder-block h-4 w-full" aria-hidden="true" />
            <div className="placeholder-block h-4 w-5/6" aria-hidden="true" />
        </div>
        <div className="placeholder-block h-24 w-full" aria-hidden="true" />
    </div>
);

export default DetailShape;
