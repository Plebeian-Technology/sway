const HomeShape: React.FC = () => (
    <div className="flex flex-col gap-6">
        <div className="placeholder-block h-10 w-1/2" aria-hidden="true" />
        <div className="placeholder-block h-40 w-full" aria-hidden="true" />
        <div className="grid gap-4 md:grid-cols-2">
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
            <div className="placeholder-block h-24 w-full" aria-hidden="true" />
        </div>
    </div>
);

export default HomeShape;
