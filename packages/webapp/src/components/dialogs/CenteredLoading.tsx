import { CircularProgress } from "@material-ui/core"

const CenteredLoading = ({ message }: { message?: string }) => {
    return (
        <div style={{ textAlign: "center", margin: "0 auto" }}>
            <CircularProgress color={"primary"} />
            {message && <span>{message}</span>}
        </div>
    )
}

export default CenteredLoading;