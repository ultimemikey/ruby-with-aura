require "monitor"

module Aura
  module DB

    class MemoryAdapter
      CREATE = /\Acreate\s+table\s+(?:if\s+not\s+exists\s+)?([a-z0-9_]+)\s*\((.+)\)\s*;?\z/mi
      INSERT = /\Ainsert\s+into\s+([a-z0-9_]+)\s*\(([^)]*)\)\s*values\s*\((.*)\)\s*;?\z/mi
      SELECT = /\Aselect\s+\*\s+from\s+([a-z0-9_]+)(?:\s+where\s+(.+?))?\s*;?\z/mi
      UPDATE = /\Aupdate\s+([a-z0-9_]+)\s+set\s+(.+?)(?:\s+where\s+(.+?))?\s*;?\z/mi
      DELETE = /\Adelete\s+from\s+([a-z0-9_]+)(?:\s+where\s+(.+?))?\s*;?\z/mi

      def initialize(**_options)
        @tables = {}
        @lock   = Monitor.new
      end

      def query(sql, *binds)
        @lock.synchronize do
          match = SELECT.match(sql.to_s.strip)
          raise ArgumentError, "unsupported query: #{sql}" unless match

          table = @tables[match[1].downcase]
          return [] unless table

          conditions = parse_where(match[2], binds)
          table[:rows].select { |row| matches?(row, conditions) }.map(&:dup)
        end
      end

      def execute(sql, *binds)
        @lock.synchronize { run(sql.to_s.strip, binds) }
      end

      def transaction
        @lock.synchronize do
          snapshot = deep_dup(@tables)
          begin
            yield self
          rescue StandardError
            @tables = snapshot
            raise
          end
        end
      end

      def tables
        @lock.synchronize { @tables.keys.sort }
      end

      private

      def run(sql, binds)
        if (match = CREATE.match(sql))
          create_table(match[1], match[2])
        elsif (match = INSERT.match(sql))
          insert(match[1], match[2], match[3], binds)
        elsif (match = UPDATE.match(sql))
          update(match[1], match[2], match[3], binds)
        elsif (match = DELETE.match(sql))
          delete(match[1], match[2], binds)
        else
          raise ArgumentError, "unsupported statement: #{sql}"
        end
      end

      def create_table(name, columns)
        column_names = columns.split(",").map { |defn| defn.strip.split(/\s+/).first }.reject(&:empty?)
        @tables[name.downcase] ||= { columns: column_names, rows: [] }
        0
      end

      def insert(name, columns, values, binds)
        table     = fetch(name)
        cols      = columns.split(",").map(&:strip).reject(&:empty?)
        vals      = split_top_level(values, ",")
        raise ArgumentError, "column/value count mismatch" if cols.length != vals.length

        bind_iter = binds.dup
        row = {}
        cols.each_with_index { |col, index| row[col] = literal_or_bind(vals[index], bind_iter) }
        table[:columns] |= cols
        table[:rows] << row
        1
      end

      def update(name, assignments, where, binds)
        table     = fetch(name)
        bind_iter = binds.dup

        sets = assignments.split(",").map do |assign|
          col, value = assign.split(/\s*=\s*/, 2)
          raise ArgumentError, "invalid assignment: #{assign}" if value.nil?

          [col.strip, literal_or_bind(value, bind_iter)]
        end

        conditions = parse_where(where, bind_iter)
        updated = 0
        table[:rows].each do |row|
          next unless matches?(row, conditions)

          sets.each { |col, value| row[col] = value }
          updated += 1
        end
        updated
      end

      def delete(name, where, binds)
        table      = fetch(name)
        conditions = parse_where(where, binds)
        before     = table[:rows].length
        table[:rows].reject! { |row| matches?(row, conditions) }
        before - table[:rows].length
      end

      def parse_where(clause, binds)
        return [] if clause.nil? || clause.strip.empty?

        bind_iter = binds.dup
        clause.split(/\s+and\s+/i).map do |cond|
          col, value = cond.split(/\s*=\s*/, 2)
          raise ArgumentError, "invalid condition: #{cond}" if value.nil?

          [col.strip, literal_or_bind(value, bind_iter)]
        end
      end

      def matches?(row, conditions)
        conditions.all? { |col, value| row[col].to_s == value.to_s }
      end

      def fetch(name)
        @tables[name.downcase] || raise(ArgumentError, "no such table: #{name}")
      end

      def literal_or_bind(token, bind_iter)
        trimmed = token.strip
        return bind_iter.shift if trimmed == "?"

        literal(trimmed)
      end

      def literal(token)
        value = token.strip
        return value[1..-2] if quoted?(value)
        return value.to_i if value.match?(/\A-?\d+\z/)
        return value.to_f if value.match?(/\A-?\d+\.\d+\z/)
        return nil if value.casecmp?("null")
        return true if value.casecmp?("true")
        return false if value.casecmp?("false")

        value
      end

      def quoted?(value)
        return false if value.length < 2

        (value.start_with?("'") && value.end_with?("'")) ||
          (value.start_with?('"') && value.end_with?('"'))
      end

      def split_top_level(str, sep)
        parts  = []
        buffer = +""
        quote  = nil

        str.each_char do |char|
          if quote
            buffer << char
            quote = nil if char == quote
          elsif char == "'" || char == '"'
            quote = char
            buffer << char
          elsif char == sep
            parts << buffer
            buffer = +""
          else
            buffer << char
          end
        end

        parts << buffer
        parts.map(&:strip)
      end

      def deep_dup(object)
        case object
        when Hash  then object.each_with_object({}) { |(key, value), acc| acc[key] = deep_dup(value) }
        when Array then object.map { |item| deep_dup(item) }
        else object
        end
      end
    end
  end
end
