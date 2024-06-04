output "secrets" {
  sensitive = true

  value = {
    ADMIN_PHONES: google_secret_manager_secret.ADMIN_PHONES.id,
    GOOGLE_MAPS_API_KEY: google_secret_manager_secret.GOOGLE_MAPS_API_KEY.id,
    GOOGLE_RECAPTCHA_SECRET_KEY: google_secret_manager_secret.GOOGLE_RECAPTCHA_SECRET_KEY.id,
    SECRET_KEY_BASE: google_secret_manager_secret.SECRET_KEY_BASE.id,
    SWAY_DATABASE_PASSWORD: google_secret_manager_secret.SWAY_DATABASE_PASSWORD.id,
    TWILIO_ACCOUNT_SID: google_secret_manager_secret.TWILIO_ACCOUNT_SID.id,
    TWILIO_AUTH_TOKEN: google_secret_manager_secret.TWILIO_AUTH_TOKEN.id,
    TWILIO_VERIFY_SERVICE_SID: google_secret_manager_secret.TWILIO_VERIFY_SERVICE_SID.id,
    VAPID_PRIVATE_KEY: google_secret_manager_secret.VAPID_PRIVATE_KEY.id,
    VAPID_PUBLIC_KEY: google_secret_manager_secret.VAPID_PUBLIC_KEY.id,
    VITE_GOOGLE_MAPS_API_KEY: google_secret_manager_secret.VITE_GOOGLE_MAPS_API_KEY.id,
    VITE_GOOGLE_RECAPTCHA_SITE_KEY: google_secret_manager_secret.VITE_GOOGLE_RECAPTCHA_SITE_KEY.id,
    SWAY_DATABASE_PASSWORD: google_secret_manager_secret.SWAY_DATABASE_PASSWORD.id,
    LITESTREAM_ACCESS_KEY_ID: google_secret_manager_secret.LITESTREAM_ACCESS_KEY_ID.id,
    LITESTREAM_SECRET_ACCESS_KEY: google_secret_manager_secret.LITESTREAM_SECRET_ACCESS_KEY.id,
  }
}