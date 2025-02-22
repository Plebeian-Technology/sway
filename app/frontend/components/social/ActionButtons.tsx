import { Children, cloneElement, Fragment, isValidElement, PropsWithChildren } from "react";

const ActionButtons: React.FC<PropsWithChildren> = ({ children }) => {
    return (
        <div className="row">
            <div className="col">
                <div className="row">
                    <div className="col text-center">
                        <h3>Do more to increase your sway.</h3>
                    </div>
                </div>
                <div className="d-flex flex-row align-items-stretch justify-content-center gap-2 my-2">
                    {Children.map(children, (child, i) =>
                        isValidElement(child) ? (
                            cloneElement(child, { ...(child.props as Record<string, any>) })
                        ) : (
                            <Fragment key={`layout-child-${i}`}></Fragment>
                        ),
                    )}
                </div>
            </div>
        </div>
    );
};

export default ActionButtons;
