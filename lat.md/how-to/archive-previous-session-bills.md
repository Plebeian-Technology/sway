# Archive bills after a session rollover

Archive a locale's older unfeatured bills after its new session starts. [[bill-session-archiving]] defines eligibility and the preserved history.

1. Update the locale's session declarations in `config/sway_locales/` and synchronize them with the database using the existing locale seeding procedure in [[add-a-sway-locale]]. Keep completed sessions declared and mark the new session active.
2. Apply database migrations with `dip run rails db:migrate`.
3. Preview one locale's eligible bills using the task in [[lib/tasks/archive_previous_session_bills.rake]]:

   ```bash
   dip run bundle exec rake 'sway:bills:archive_previous_sessions[baltimore-maryland-united_states]'
   ```

4. Finish or stop the locale's pipeline and wait for its worker to exit. Allow outstanding summary batches to settle. Review the locale, current session, candidate count and bill identifiers, then apply the archive:

   ```bash
   dip run bundle exec rake 'sway:bills:archive_previous_sessions[baltimore-maryland-united_states,apply]'
   ```

5. If apply reports that the pipeline is busy, wait for the locale's active work to finish and retry apply. Preview again to confirm that no eligible bills remain. Inspect retained archives in `dip run rails c` through `Bill.unscoped.where(sway_locale: locale).where.not(archived_at: nil)`. Application queries and direct links exclude them.
