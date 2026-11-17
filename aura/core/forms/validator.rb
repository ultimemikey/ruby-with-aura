module Aura
  module Core
    module Forms

      module Validator
        EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
        INTEGER = /\A-?\d+\z/

        def self.validate(input, rules = {})
          errors = {}

          rules.each do |field, spec|
            spec  = { required: true } if spec == true
            spec  = {} unless spec.is_a?(::Hash)
            value = extract(input, field)
            message = check(field, value, spec)
            errors[field.to_sym] = message if message
          end

          errors
        end

        def self.extract(input, field)
          return nil unless input.respond_to?(:[])

          input[field] || input[field.to_s] || input[field.to_sym]
        end

        def self.check(field, value, spec)
          str = value.nil? ? "" : value.to_s
          label = spec[:label] || field

          return spec[:message] || "#{label} is required" if spec[:required] && str.strip.empty?
          return nil if str.empty?

          return spec[:message] || "#{label} must be a valid email" if spec[:email] && !str.match?(EMAIL)
          return spec[:message] || "#{label} must be an integer"    if spec[:integer] && !str.match?(INTEGER)
          return spec[:message] || "#{label} is invalid"            if spec[:format] && !spec[:format].match?(str)
          return spec[:message] || "#{label} is not allowed"        if spec[:in] && !Array(spec[:in]).map(&:to_s).include?(str)
          return spec[:message] || "#{label} must be at least #{spec[:min]} characters" if spec[:min] && str.length < spec[:min]
          return spec[:message] || "#{label} must be at most #{spec[:max]} characters"  if spec[:max] && str.length > spec[:max]

          nil
        end
      end
    end
  end
end
