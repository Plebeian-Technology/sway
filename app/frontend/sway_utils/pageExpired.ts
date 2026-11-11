interface IFlash {
    page_expired?: boolean;
}

// @lat: [[page-expired-flash-flag-and-c21-01#Why IPageWithFlash.props is a bag, not { flash?: unknown }]]
interface IPageWithFlash {
    props: Record<string, unknown>;
}

// @lat: [[page-expired-flash-flag-and-c21-01#Why the redirect target and the flag both matter]]
export const pageExpired = (page: IPageWithFlash): boolean =>
    (page.props.flash as IFlash | undefined)?.page_expired === true;

export default pageExpired;
