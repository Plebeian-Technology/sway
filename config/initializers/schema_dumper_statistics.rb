# frozen_string_literal: true

# @lat: [[query-plan-indexes#Statistics the planner reads]]
ActiveSupport.on_load(:active_record) do
  ActiveRecord::SchemaDumper.ignore_tables |= ["sqlite_stat1"]
end
