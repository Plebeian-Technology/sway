import { render, screen } from "@testing-library/react";
import LlmSummaryTestimonyAttachmentWarning from "app/frontend/components/admin/creator/llm-summary/LlmSummaryTestimonyAttachmentWarning";

describe("LlmSummaryTestimonyAttachmentWarning", () => {
    it("returns null when attachments is null", () => {
        const { container } = render(<LlmSummaryTestimonyAttachmentWarning attachments={null} />);
        expect(container.firstChild).toBeNull();
    });

    it("returns null when all attachments succeeded", () => {
        const { container } = render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    {
                        filename: "testimony-1.pdf",
                        download_status: "succeeded",
                        extraction_status: "succeeded",
                        error: null,
                    },
                    {
                        filename: "testimony-2.pdf",
                        download_status: "succeeded",
                        extraction_status: "succeeded",
                        error: null,
                    },
                ]}
            />,
        );
        expect(container.firstChild).toBeNull();
    });

    it("renders only failed rows with the paste-testimony trailer, singular title for one failure", () => {
        render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    {
                        filename: "testimony-1.pdf",
                        download_status: "failed",
                        extraction_status: "succeeded",
                        error: "timeout",
                    },
                    {
                        filename: "testimony-2.pdf",
                        download_status: "succeeded",
                        extraction_status: "succeeded",
                        error: null,
                    },
                ]}
            />,
        );

        expect(screen.getByTestId("llm-testimony-attachment-warning")).toBeInTheDocument();
        expect(screen.getByText("Testimony attachment issue")).toBeInTheDocument();
        expect(screen.getByText(/testimony-1\.pdf.*download failed.*timeout/)).toBeInTheDocument();
        expect(screen.queryByText(/testimony-2\.pdf/)).toBeNull();
        expect(
            screen.getByText(
                "Paste the testimony text into Supplemental testimony below and click Save testimony if needed.",
            ),
        ).toBeInTheDocument();
    });

    // @lat: [[testimony-attachment-warning-lists#Test notes]]
    it("names the click that saves the pasted testimony, not just the field", () => {
        render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    {
                        filename: "testimony-1.pdf",
                        download_status: "failed",
                        extraction_status: "not_attempted",
                        error: "timeout",
                    },
                ]}
            />,
        );

        expect(screen.getByTestId("llm-testimony-attachment-warning")).toHaveTextContent(/click Save testimony/i);
    });

    // @lat: [[attachment-status-label-mapping#Test notes]]
    it("labels an extraction failure distinctly from a download failure and pluralizes the title for multiple failures", () => {
        render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    {
                        filename: "testimony-1.pdf",
                        download_status: "failed",
                        extraction_status: "succeeded",
                        error: null,
                    },
                    {
                        filename: "testimony-2.pdf",
                        download_status: "succeeded",
                        extraction_status: "extraction_failed",
                        error: null,
                    },
                ]}
            />,
        );

        expect(screen.getByText("Testimony attachment issues")).toBeInTheDocument();
        expect(screen.getByText(/testimony-1\.pdf.*download failed/)).toBeInTheDocument();
        expect(screen.getByText(/testimony-2\.pdf.*could not extract text/)).toBeInTheDocument();
    });

    // @lat: [[testimony-attachment-warning-lists#Test notes]]
    describe("status labels (C1-WR-01)", () => {
        const row = (download: string, extraction: string, error: string | null = null) => {
            render(
                <LlmSummaryTestimonyAttachmentWarning
                    attachments={[
                        {
                            filename: "t.pdf",
                            download_status: download,
                            extraction_status: extraction,
                            error,
                        },
                    ]}
                />,
            );
            return screen.getByText(/t\.pdf/).textContent;
        };

        it.each([
            ["pending", "download not finished"],
            ["failed", "download failed"],
            ["not_attempted", "not attempted — nothing was tried"],
            ["skipped_time_budget", "not downloaded — time budget exhausted"],
        ])("labels download_status %s as %s", (status, label) => {
            expect(row(status, "not_attempted")).toBe(`t.pdf — ${label}`);
        });

        it.each([
            ["pending", "not extracted yet"],
            ["extraction_failed", "could not extract text"],
            ["skipped_download_failed", "not extracted — download failed"],
            ["skipped_time_budget", "not extracted — time budget exhausted"],
            ["not_attempted", "not attempted — nothing was tried"],
        ])("labels extraction_status %s as %s once the download succeeded", (status, label) => {
            expect(row("succeeded", status)).toBe(`t.pdf — ${label}`);
        });

        it("renders an unrecognized status verbatim rather than mislabelling it", () => {
            expect(row("succeeded", "some_future_status")).toBe("t.pdf — some_future_status");
        });
    });

    // @lat: [[testimony-attachment-warning-lists#Test notes]]
    describe("reused_prior_run is not an issue to re-paste (C1-WR-01)", () => {
        const reused = {
            filename: "BCFD 25-0064.pdf",
            download_status: "succeeded",
            extraction_status: "reused_prior_run",
            error: "this run could not re-extract (mutool exited 1); showing text captured by a previous run",
        };

        it("reports it under its own heading, not as an attachment issue", () => {
            render(<LlmSummaryTestimonyAttachmentWarning attachments={[reused]} />);

            expect(screen.queryByTestId("llm-testimony-attachment-warning")).toBeNull();
            const notice = screen.getByTestId("llm-testimony-attachment-reused");
            expect(notice.textContent).toContain("BCFD 25-0064.pdf");
            expect(notice.textContent).toContain("using text captured by an earlier run");
        });

        it("tells the operator the text is already in hand instead of asking for a paste", () => {
            render(<LlmSummaryTestimonyAttachmentWarning attachments={[reused]} />);

            expect(screen.getByTestId("llm-testimony-attachment-reused").textContent).not.toMatch(/paste/i);
            expect(screen.queryByText(/Paste the testimony text into Supplemental testimony/)).toBeNull();
        });

        it("keeps genuinely missing rows in the issues list alongside a reused row", () => {
            render(
                <LlmSummaryTestimonyAttachmentWarning
                    attachments={[
                        reused,
                        {
                            filename: "scan.pdf",
                            download_status: "succeeded",
                            extraction_status: "extraction_failed",
                            error: "extraction produced no text layer (no OCR attempted)",
                        },
                    ]}
                />,
            );

            const issues = screen.getByTestId("llm-testimony-attachment-warning");
            expect(issues.textContent).toContain("scan.pdf");
            expect(issues.textContent).not.toContain("BCFD 25-0064.pdf");
            expect(screen.getByTestId("llm-testimony-attachment-reused").textContent).toContain("BCFD 25-0064.pdf");
        });
    });

    // @lat: [[attachment-status-label-mapping#Test notes]]
    describe("a truncated-but-succeeded extraction is not silent (A-WR-03)", () => {
        const truncated = {
            filename: "BUILD Testimony 25-0064.pdf",
            download_status: "succeeded",
            extraction_status: "succeeded",
            error: "extracted text truncated to 500000 chars (was 731882)",
        };

        it("surfaces the truncation note the mirror recorded", () => {
            render(<LlmSummaryTestimonyAttachmentWarning attachments={[truncated]} />);

            const notice = screen.getByTestId("llm-testimony-attachment-truncated");
            expect(notice.textContent).toContain("BUILD Testimony 25-0064.pdf");
            expect(notice.textContent).toContain("truncated to 500000 chars");
        });

        it("does not file it as a document whose text is missing entirely", () => {
            render(<LlmSummaryTestimonyAttachmentWarning attachments={[truncated]} />);

            expect(screen.queryByTestId("llm-testimony-attachment-warning")).toBeNull();
            expect(screen.queryByTestId("llm-testimony-attachment-reused")).toBeNull();
        });

        it("keeps a clean extraction silent, so the new list cannot fire on every bill", () => {
            const { container } = render(
                <LlmSummaryTestimonyAttachmentWarning
                    attachments={[
                        {
                            filename: "clean.pdf",
                            download_status: "succeeded",
                            extraction_status: "succeeded",
                            error: null,
                        },
                    ]}
                />,
            );

            expect(container.firstChild).toBeNull();
        });

        it("keeps the three lists separate when all of them have a row", () => {
            render(
                <LlmSummaryTestimonyAttachmentWarning
                    attachments={[
                        truncated,
                        {
                            filename: "scan.pdf",
                            download_status: "succeeded",
                            extraction_status: "extraction_failed",
                            error: "extraction produced no text layer (no OCR attempted)",
                        },
                        {
                            filename: "BCFD 25-0064.pdf",
                            download_status: "succeeded",
                            extraction_status: "reused_prior_run",
                            error: "showing text captured by a previous run",
                        },
                    ]}
                />,
            );

            expect(screen.getByTestId("llm-testimony-attachment-warning").textContent).toContain("scan.pdf");
            expect(screen.getByTestId("llm-testimony-attachment-reused").textContent).toContain("BCFD 25-0064.pdf");
            expect(screen.getByTestId("llm-testimony-attachment-truncated").textContent).toContain(
                "BUILD Testimony 25-0064.pdf",
            );
        });
    });

    // @lat: [[admin-mirror-display-vs-identity#Test notes on the AttachmentRows key]]
    it("renders one row per failed attachment even when two share a filename", () => {
        render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    {
                        filename: "Testimony.pdf",
                        download_status: "failed",
                        extraction_status: "pending",
                        error: "HTTP 404",
                    },
                    {
                        filename: "Testimony.pdf",
                        download_status: "failed",
                        extraction_status: "pending",
                        error: "HTTP 500",
                    },
                ]}
            />,
        );

        expect(screen.getAllByText(/Testimony\.pdf/).length).toBe(2);
        expect(screen.getByText(/HTTP 404/)).toBeInTheDocument();
        expect(screen.getByText(/HTTP 500/)).toBeInTheDocument();
    });

    // @lat: [[admin-mirror-display-vs-identity#Test notes on the AttachmentRows key]]
    it("renders one row per failed attachment when two share a filename and carry their ids", () => {
        render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    {
                        filename: "Testimony.pdf",
                        attachment_id: "940",
                        download_status: "failed",
                        extraction_status: "pending",
                        error: "HTTP 404",
                    },
                    {
                        filename: "Testimony.pdf",
                        attachment_id: "941",
                        download_status: "failed",
                        extraction_status: "pending",
                        error: "HTTP 500",
                    },
                ]}
            />,
        );

        expect(screen.getAllByText(/Testimony\.pdf/).length).toBe(2);
        expect(screen.getByText(/HTTP 404/)).toBeInTheDocument();
        expect(screen.getByText(/HTTP 500/)).toBeInTheDocument();
    });

    it("names an attachment whose upstream filename was missing instead of emitting a blank row", () => {
        render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    { filename: "", download_status: "failed", extraction_status: "pending", error: null },
                    { filename: "", download_status: "failed", extraction_status: "pending", error: "HTTP 500" },
                ]}
            />,
        );

        const rows = screen.getAllByText(/\(unnamed attachment\)/);
        expect(rows.length).toBe(2);
        expect(rows[0].textContent).toBe("(unnamed attachment) — download failed");
    });

    it("omits the error suffix when error is null", () => {
        render(
            <LlmSummaryTestimonyAttachmentWarning
                attachments={[
                    {
                        filename: "testimony-1.pdf",
                        download_status: "failed",
                        extraction_status: "succeeded",
                        error: null,
                    },
                ]}
            />,
        );

        const row = screen.getByText(/testimony-1\.pdf/);
        expect(row.textContent).toBe("testimony-1.pdf — download failed");
    });

    // @lat: [[attachment-status-label-mapping#Test notes]]
    describe("a document the classifier read and judged not testimony", () => {
        const denied = {
            filename: "agency-report.pdf",
            download_status: "succeeded",
            extraction_status: "content_denied",
            error: "the model read this document and judged it not testimony, so its text is withheld",
        };

        it("renders it under its own heading with the verdict and the way out", () => {
            render(<LlmSummaryTestimonyAttachmentWarning attachments={[denied]} />);

            expect(screen.getByTestId("llm-testimony-attachment-denied")).toBeTruthy();
            expect(screen.getByText(/Document read and judged not testimony/)).toBeTruthy();
            expect(screen.getByText(/agency-report\.pdf/).textContent).toContain("read and judged not testimony");
            expect(screen.getByText(/paste that document.s text into Supplemental testimony/i)).toBeTruthy();
        });

        it("does not file it as a document whose text is missing", () => {
            render(<LlmSummaryTestimonyAttachmentWarning attachments={[denied]} />);

            expect(screen.queryByTestId("llm-testimony-attachment-warning")).toBeNull();
        });

        // @lat: [[attachment-status-label-mapping#Test notes]]
        it("says what the classifier decided even when this run's download failed", () => {
            render(<LlmSummaryTestimonyAttachmentWarning attachments={[{ ...denied, download_status: "failed" }]} />);

            const row = screen.getByText(/agency-report\.pdf/);
            expect(row.textContent).toContain("read and judged not testimony");
            expect(row.textContent).not.toContain("download failed");
        });
    });
});
