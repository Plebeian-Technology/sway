# ActiveStorage External Asset Mirroring — Implementation Plan

## Context

Organization icons and legislator photos are currently stored as string paths/URLs in the database. Organization icons use a custom `SwayGoogleCloudStorage` module with relative paths (e.g. `"logo.svg"`) that get concatenated with a GCS bucket base URL on the frontend. Legislator photos store full external URLs from Congress.gov/OpenStates APIs. This is fragile — external URLs break, there's no local control over assets, and the frontend URL construction is error-prone.

This plan migrates to ActiveStorage as the canonical asset store. External URLs get mirrored into app-managed storage. Admin uploads switch from custom GCS signed-URL flow to ActiveStorage direct upload (browser → GCS, never through Rails). String columns remain as a derived URL cache for fast Inertia.js serialization.

## Scope

- `organizations.icon_path` → rename to `icon_url`, add `has_one_attached :icon`
- `sway_locales.icon_path` → rename to `icon_url`, add `has_one_attached :icon`
- `legislators.photo_url` → keep name, add `has_one_attached :photo`
- New `ExternalAssetMirrorService` + `MirrorExternalAssetJob`
- Admin icon upload: replace GCS signed-URL flow with ActiveStorage direct upload
- Backfill rake task for existing data

---

## Phase 1: ActiveStorage Infrastructure

### 1.1 Install base ActiveStorage migration

The base `create_active_storage_tables` migration is missing (only amendment migrations exist at `db/migrate/20250104040900-02`). Run `rails active_storage:install` to generate it, then migrate.

### 1.2 Configure GCS storage service

**`config/storage.yml`** — add:

```yaml
google:
    service: GCS
    project: sway-421916
    credentials: <%= Rails.root.join("config/keys/sway-bucket-storage.json") %>
    bucket: sway-assets
```

### 1.3 Update environment configs

- **`config/environments/production.rb`**: change `config.active_storage.service` from `:local` to `:google`
- **`config/environments/production.rb`**: add `default_url_options` for absolute URL generation outside request context
- **`config/environments/development.rb`**: add `default_url_options` (`localhost:3333`, https)
- Keep dev/test on `:local` / `:test`

### 1.4 GCS credentials initializer

**New file: `config/initializers/active_storage_gcs_credentials.rb`**
Ensure the existing `SwayGoogleCloudStorage.credentials` method writes the keyfile before ActiveStorage initializes (production only).

### 1.5 Install `@rails/activestorage` npm package

```bash
npm install @rails/activestorage
```

Initialize in frontend entrypoint: `ActiveStorage.start()`.

### 1.6 Add `down` gem

For robust HTTP downloads in the mirror service.

---

## Phase 2: Database Migration

**New migration: `rename_icon_path_to_icon_url`**

```ruby
rename_column :organizations, :icon_path, :icon_url
rename_column :sway_locales, :icon_path, :icon_url
# legislators.photo_url stays as-is
```

---

## Phase 3: Models

### 3.1 Organization (`app/models/organization.rb`)

- Add `has_one_attached :icon`
- Remove `include SwayGoogleCloudStorage` and `remove_icon` method
- Add `after_save :update_icon_url_from_attachment` — computes `rails_storage_proxy_url(icon)` and writes to `icon_url` column
- Update `to_builder` / `to_simple_builder`: `icon_path` → `icon_url`

### 3.2 Legislator (`app/models/legislator.rb`)

- Add `has_one_attached :photo`
- Add `after_save` callback: when `photo_url` changes to an external URL, enqueue `MirrorExternalAssetJob`
- Add `after_save :update_photo_url_from_attachment` — when photo is attached and URL isn't external, update `photo_url` to ActiveStorage proxy URL
- `to_builder` unchanged (still outputs `photo_url`)

### 3.3 SwayLocale (`app/models/sway_locale.rb`)

- Add `has_one_attached :icon`
- Add `after_save :update_icon_url_from_attachment` (same pattern as Organization)
- Update `to_builder` (line 165): `icon_path` → `icon_url`

---

## Phase 4: ExternalAssetMirrorService + Job

### 4.1 Service (`app/services/external_asset_mirror_service.rb`)

- `call(record:, attachment_name:, url_column:)`
- **Skip** when URL is blank, non-HTTP, or already internal (`*.sway.vote`, `storage.googleapis.com/sway-assets`)
- **Download** external asset via `Down.download`
- **Attach** to ActiveStorage, compute proxy URL, update string column
- **404** → purge attachment, set column to `nil`
- **Other errors** → log, preserve original URL (soft fail)

### 4.2 Background job (`app/jobs/mirror_external_asset_job.rb`)

- `perform(record_class_name, record_id, attachment_name, url_column)`
- Retry with polynomial backoff, 3 attempts
- No-op if record deleted

---

## Phase 5: Controller Updates

### 5.1 Organizations controller (`app/controllers/organizations_controller.rb`)

- Remove `include SwayGoogleCloudStorage`
- Change permitted param: `icon_path` → `icon_signed_id`
- In create/update: `organization.icon.attach(param[:icon_signed_id])` when present
- Remove `remove_icon` call (ActiveStorage handles purge)

### 5.2 Bills controller (`app/controllers/bills_controller.rb`)

- Keep `include SwayGoogleCloudStorage` (still needed for audio)
- Update `organizations_params`: `icon_path` → `icon_signed_id`
- Remove the `remove_icon` private method for organizations
- Update organization-saving logic to attach via `signed_id`

### 5.3 Buckets::AssetsController

- Keep as-is (still needed for audio uploads). Icon uploads bypass it via ActiveStorage direct upload endpoint.

---

## Phase 6: Frontend Updates

### 6.1 TypeScript interfaces (`app/frontend/index.d.ts`)

- `ISwayLocale.icon_path` → `icon_url` (line 118)
- `IOrganizationBase.icon_path` → `icon_url` (line 366)
- `ILegislator.photo_url` — unchanged

### 6.2 Admin creator types (`app/frontend/components/admin/creator/types/index.ts`)

- `TOrganizationOption`: `icon_path` → `icon_url`, add `icon_signed_id?: string`

### 6.3 OrganizationIcon (`app/frontend/components/organizations/OrganizationIcon.tsx`)

- Remove `SWAY_ASSETS_BUCKET_BASE_URL` concatenation
- Use `icon_url` directly as a full URL (it's already absolute from the backend)
- Change `icon_path` references to `icon_url`

### 6.4 BillCreatorOrganization (`app/frontend/components/admin/creator/BillCreatorOrganization.tsx`)

- Replace `FileUploadModal` + presigned GCS flow with ActiveStorage `DirectUpload`
- `import { DirectUpload } from "@rails/activestorage"`
- On file select: `DirectUpload` → POST `/rails/active_storage/direct_uploads` → browser uploads to GCS → store `signed_id` in form data
- New component: `DirectUploadModal.tsx` (keep `FileUploadModal` for audio)

### 6.5 Other frontend files (icon_path → icon_url)

- `BillArgumentsOrganization.tsx` line 40
- `BillComponent.tsx` line 38 (default org constant)
- `BillCreatorOrganizations.tsx` line 33
- `UserOrganizationMembership.tsx` line 23
- `UserOrganizationMemberships_List.tsx` lines 20-21

### 6.6 LegislatorCardAvatar

- No changes needed (already uses `photo_url` directly)

---

## Phase 7: Seed Updates

### 7.1 SwayLocale seed (`db/seeds/models/sway_locale.rb`)

- Line 35: `icon_path` → `icon_url`

### 7.2 Legislator seeds

- No changes to seed preparers — they still return external URLs
- The `after_save` callback handles mirroring automatically

---

## Phase 8: Backfill Rake Task

**New file: `lib/tasks/backfill_active_storage_assets.rake`**

- **Organizations**: for each with `icon_url`, if relative path → construct full GCS URL (`https://storage.googleapis.com/sway-assets/{path}`), download, attach. If external URL → mirror via service.
- **Legislators**: for each with external `photo_url` → mirror via service.
- **SwayLocales**: for each with `icon_url` → download from GCS bucket, attach.
- Log counts: mirrored, skipped, cleared_404, failed_soft.

---

## Phase 9: Tests

- **Service specs** (`spec/services/external_asset_mirror_service_spec.rb`): skip rules, mirror success, 404→nil, non-404 soft-fail, idempotency
- **Job specs** (`spec/jobs/mirror_external_asset_job_spec.rb`): delegates to service, handles deleted record
- **Model specs**: after_save callbacks update URL columns correctly
- **Request specs**: organization create/update with `icon_signed_id`
- **Frontend**: update existing tests for `icon_path` → `icon_url`
- **Factory** (`spec/factories/organization.rb`): `icon_path` → `icon_url`

---

## Phase 10: Cleanup (deferred, post-verification)

- Remove `SWAY_ASSETS_BUCKET_BASE_URL` from frontend constants
- Remove presigned upload hooks (`usePresignedBucketUpload`, `usePresignedBucketUploadUrl`) — only after audio is also migrated
- Remove `SwayGoogleCloudStorage` from bills controller — only after audio migrated

---

## Files Modified (key)

| File                                                                | Change                                          |
| ------------------------------------------------------------------- | ----------------------------------------------- |
| `config/storage.yml`                                                | Add GCS service                                 |
| `config/environments/production.rb`                                 | Switch to `:google`, add URL host               |
| `config/environments/development.rb`                                | Add URL host                                    |
| `app/models/organization.rb`                                        | `has_one_attached :icon`, callbacks, remove GCS |
| `app/models/legislator.rb`                                          | `has_one_attached :photo`, mirror callback      |
| `app/models/sway_locale.rb`                                         | `has_one_attached :icon`, callbacks             |
| `app/controllers/organizations_controller.rb`                       | `icon_signed_id` param, remove GCS              |
| `app/controllers/bills_controller.rb`                               | Update org icon params                          |
| `app/frontend/index.d.ts`                                           | `icon_path` → `icon_url`                        |
| `app/frontend/components/organizations/OrganizationIcon.tsx`        | Remove URL construction                         |
| `app/frontend/components/admin/creator/BillCreatorOrganization.tsx` | DirectUpload                                    |
| `spec/factories/organization.rb`                                    | `icon_path` → `icon_url`                        |

## New Files

| File                                                    | Purpose                         |
| ------------------------------------------------------- | ------------------------------- |
| `config/initializers/active_storage_gcs_credentials.rb` | Ensure keyfile exists           |
| `db/migrate/*_rename_icon_path_to_icon_url.rb`          | Column rename                   |
| `app/services/external_asset_mirror_service.rb`         | Download + attach external URLs |
| `app/jobs/mirror_external_asset_job.rb`                 | Async mirroring                 |
| `app/frontend/components/dialogs/DirectUploadModal.tsx` | ActiveStorage direct upload UI  |
| `lib/tasks/backfill_active_storage_assets.rake`         | Migrate existing data           |

## New Dependencies

- `down` gem (HTTP downloads)
- `@rails/activestorage` npm package

---

## Verification

1. **Dev smoke test**: Create organization with icon via admin creator → verify DirectUpload works, icon renders
2. **Mirror test**: Seed a legislator with external photo_url → verify job runs, photo attached, URL updated
3. **404 test**: Set a legislator photo_url to a known-404 URL → verify it gets cleared
4. **Backfill test**: Run rake task in dev → verify all existing assets migrated
5. **RSpec**: `bundle exec rspec spec/services/ spec/jobs/ spec/models/ spec/requests/`
6. **Frontend**: `npx tsc` (type checking), `npx eslint app/frontend/`
