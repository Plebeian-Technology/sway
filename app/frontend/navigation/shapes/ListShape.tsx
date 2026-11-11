const ListShape: React.FC = () => (
    <div className="flex flex-col gap-6">
        <div className="placeholder-block h-8 w-1/3" aria-hidden="true" />
        <div className="flex gap-2">
            <div className="placeholder-block h-8 w-24" aria-hidden="true" />
            <div className="placeholder-block h-8 w-24" aria-hidden="true" />
            <div className="placeholder-block h-8 w-40" aria-hidden="true" />
        </div>
        <div className="flex flex-col gap-4">
            <div className="placeholder-block h-20 w-full" aria-hidden="true" />
            <div className="placeholder-block h-20 w-full" aria-hidden="true" />
            <div className="placeholder-block h-20 w-full" aria-hidden="true" />
            <div className="placeholder-block h-20 w-full" aria-hidden="true" />
            <div className="placeholder-block h-20 w-full" aria-hidden="true" />
            <div className="placeholder-block h-20 w-full" aria-hidden="true" />
        </div>
    </div>
);

export default ListShape;
