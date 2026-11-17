module Aura
  module DB

    class Record
      class << self
        attr_writer :table

        def table
          @table ||= derived_table
        end

        def adapter
          Aura::DB.adapter
        end

        def all
          adapter.query("SELECT * FROM #{sql_identifier(table, :table)}")
        end

        def find(id)
          adapter.query("SELECT * FROM #{sql_identifier(table, :table)} WHERE id = ?", id).first
        end

        def create(attributes)
          attrs        = stringify(attributes)
          raise ArgumentError, "attributes must not be empty" if attrs.empty?

          table_name   = sql_identifier(table, :table)
          columns      = attrs.keys.map { |column| sql_identifier(column, :column) }
          placeholders = Array.new(columns.length, "?").join(", ")
          adapter.execute(
            "INSERT INTO #{table_name} (#{columns.join(', ')}) VALUES (#{placeholders})",
            *attrs.values
          )
          attrs
        end

        def update(id, attributes)
          attrs       = stringify(attributes)
          raise ArgumentError, "attributes must not be empty" if attrs.empty?

          table_name = sql_identifier(table, :table)
          assignments = attrs.keys.map do |column|
            "#{sql_identifier(column, :column)} = ?"
          end.join(", ")
          adapter.execute("UPDATE #{table_name} SET #{assignments} WHERE id = ?", *attrs.values, id)
        end

        def delete(id)
          adapter.execute("DELETE FROM #{sql_identifier(table, :table)} WHERE id = ?", id)
        end

        private

        def derived_table
          base = name.to_s.split("::").last.to_s
          base = base.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
          base.end_with?("s") ? base : "#{base}s"
        end

        def stringify(attributes)
          raise ArgumentError, "attributes must be a Hash" unless attributes.is_a?(::Hash)

          attributes.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
        end

        def sql_identifier(value, kind)
          identifier = value.to_s
          return identifier if identifier.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)

          raise ArgumentError, "Invalid SQL #{kind} identifier: #{identifier.inspect}"
        end
      end
    end
  end
end
