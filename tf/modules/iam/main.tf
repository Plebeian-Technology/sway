
################################################################################
# Roles for invoking jobs in google cloud
# https://cloud.google.com/run/docs/execute/jobs-on-schedule#required_roles
#
resource "google_service_account" "job_executor" {
  account_id   = "cloud-job-executor"
  project = var.project
  display_name = "cloud-job-executor"
  description = "Cloud Job Executor"
}

resource "google_project_iam_member" "job_executor_admin" {
  project = var.project
  role    = "roles/cloudscheduler.admin"
  member  = "serviceAccount:${google_service_account.job_executor.email}"
}

resource "google_project_iam_member" "job_executor_invoker" {
  project = var.project
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.job_executor.email}"
}
resource "google_project_iam_member" "job_executor_secrets" {
  project = var.project
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.job_executor.email}"
}

#
################################################################################


# docker run \
#   -it --rm \
#   --platform linux/amd64 \
#   -v /Users/dave/plebtech/sway-rails/storage:/data \
#   -e LITESTREAM_ACCESS_KEY_ID=DO00JDVDG829HKL28PXX \
#   -e LITESTREAM_SECRET_ACCESS_KEY=5wVxG6HVQkid5KLKDJTq4OGE9nGMoyTwYeEXDFhMYDo \
#   --entrypoint /bin/bash \
#   mirror.gcr.io/litestream/litestream@sha256:a932d9801f9d8f11ed0566aa105ef866c097c00ef1191b88a8aa0ff8e78b4071