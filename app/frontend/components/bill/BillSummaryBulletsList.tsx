import { Fragment } from "react";

const BillSummaryBulletsList: React.FC<{
    points: string[];
}> = ({ points }) => {
    return (
        <ul className="mt-3">
            {points.map((point: string, index: number) => {
                if (index === 0) {
                    const [intro, first] = point.split(":");
                    if (!first) {
                        return (
                            <li key={index} className="m-2">
                                <span>{point}</span>
                            </li>
                        );
                    }
                    return (
                        <Fragment key={index}>
                            <span>{`${intro}:`}</span>
                            <li key={index} className="m-2">
                                <span>{first}</span>
                            </li>
                        </Fragment>
                    );
                }
                return (
                    <li key={index} className="m-2">
                        <span>{point}</span>
                    </li>
                );
            })}
        </ul>
    );
};

export default BillSummaryBulletsList;
