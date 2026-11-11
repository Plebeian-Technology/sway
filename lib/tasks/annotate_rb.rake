if ENV["ANNOTATERB_SKIP_ON_DB_TASKS"].nil?
  if Rails.env.development?
    require "annotate_rb"

    AnnotateRb::Core.load_rake_tasks
  else
    # @lat: [[auxiliary-databases#The four SQLite databases#Why the annotation task refuses to run outside development]]
    namespace :annotate_rb do
      task :models do
        abort <<~MESSAGE
          annotate_rb:models must run in development (got #{Rails.env}).

          Annotations are derived from the database config, and only development
          mirrors production's multi-database shape (primary + queue). Running
          this anywhere else strips "# Database name: primary" from every
          annotated file.

          Do NOT reach for `bundle exec annotaterb models` to get around this —
          it has no environment guard and will do exactly that damage. Bring the
          development database up, or hand-edit the affected annotation blocks.
        MESSAGE
      end
    end
  end
end
