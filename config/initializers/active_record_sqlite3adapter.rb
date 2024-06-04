# https://fractaledmind.github.io/2023/09/07/enhancing-rails-sqlite-fine-tuning/

module RailsExt
  module SQLite3Adapter
    # Perform any necessary initialization upon the newly-established
    # @raw_connection -- this is the place to modify the adapter's
    # connection settings, run queries to configure any application-global
    # "session" variables, etc.
    #
    # Implementations may assume this method will only be called while
    # holding @lock (or from #initialize).
    #
    # extends https://github.com/rails/rails/blob/main/activerecord/lib/active_record/connection_adapters/sqlite3_adapter.rb#L691
    def configure_connection
      super

      @config[:pragmas].each do |key, value|
        raw_execute("PRAGMA #{key} = #{value}", "SCHEMA")
      end
    end
  end
end
