module Aura
  module DB

    class SQLiteAdapter
      attr_reader :path

      def initialize(path: ":memory:", database: nil, **_options)
        require "sqlite3"

        @path = (database || path || ":memory:").to_s
        @db   = ::SQLite3::Database.new(@path)
        @db.results_as_hash = true
      rescue LoadError => e
        raise AdapterError, "the sqlite3 gem is required for the SQLite adapter (#{e.message})"
      end

      def query(sql, *binds)
        @db.execute(sql, binds)
      end

      def execute(sql, *binds)
        @db.execute(sql, binds)
        @db.changes
      end

      def transaction
        @db.transaction { yield self }
      end
    end
  end
end
