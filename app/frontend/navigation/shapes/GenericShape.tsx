// @lat: [[navigation-placeholder-tracer#Why placeholderRegistry.ts imports no page component]]

const GenericShape: React.FC = () => (
    <div className="flex flex-col gap-4">
        <div className="placeholder-block h-8 w-2/3" aria-hidden="true" />
        <div className="placeholder-block h-4 w-full" aria-hidden="true" />
        <div className="placeholder-block h-4 w-5/6" aria-hidden="true" />
        <div className="placeholder-block h-4 w-full" aria-hidden="true" />
    </div>
);

export default GenericShape;
