require "ripper"

module Aura
  module Core

    class RipperPreprocessor

      SAFE_TYPES = %i[on_op on_ident on_kw on_nl on_newline on_sp on_ignored_nl
                      on_semicolon on_embexpr_beg on_embexpr_end].freeze

      SKIP_TYPES = %i[on_tstring_content on_regexp_content on_comment
                      on_heredoc_beg on_heredoc_end on_heredoc_body
                      on_words_sep on_symbeg on_label].freeze

      def self.process(source)
        new(source).process
      end

      def initialize(source)
        @source = source
        @tokens = Ripper.lex(source)
      end

      def process
        lines = @source.lines

        protected_ranges = build_protected_ranges

        lines = lines.each_with_index.map do |line, idx|
          row = idx + 1 
          protected_cols = protected_ranges[row] || []
          apply_line_transforms(line, protected_cols)
        end

        lines.join
      end

      private

      def build_protected_ranges
        protected = Hash.new { |h, k| h[k] = [] }

        inside_string  = false
        inside_regexp  = false
        inside_comment = false
        inside_heredoc = false

        @tokens.each do |tok|
          (row, col), type, text = tok

          case type
          when :on_tstring_beg, :on_backtick, :on_qwords_beg,
               :on_words_beg, :on_qsymbols_beg, :on_symbols_beg
            inside_string = true
          when :on_tstring_end, :on_string_end
            inside_string = false
          when :on_regexp_beg
            inside_regexp = true
          when :on_regexp_end
            inside_regexp = false
          when :on_heredoc_beg
            inside_heredoc = true
          when :on_heredoc_end
            inside_heredoc = false
          end

          if inside_string || inside_regexp || inside_heredoc ||
             type == :on_comment || type == :on_tstring_content ||
             type == :on_regexp_content

            (col...(col + text.bytesize)).each do |c|
              protected[row] << c
            end
          end
        end

        protected
      end

      USE_AURA_RE = /\Ause\s+aura\s+from\s+['"][^'"]+['"]\s*\z/.freeze
      FRAGMENT_OPEN_RE = /<>/.freeze
      FRAGMENT_CLOSE_RE = /<\/>/.freeze
      BARE_STRING_RE = /\A(\s*)(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')\s*\z/.freeze

      def apply_line_transforms(line, protected_cols)

        if USE_AURA_RE.match?(line.strip)
          match_start = line.index("use")
          if match_start && !protected_cols.include?(match_start)
            return "\n"
          end
        end

        line = line.gsub(FRAGMENT_OPEN_RE) do |m|
          start_col = Regexp.last_match.begin(0)
          protected_cols.include?(start_col) ? m : "fragment do"
        end

        line = line.gsub(FRAGMENT_CLOSE_RE) do |m|
          start_col = Regexp.last_match.begin(0)
          protected_cols.include?(start_col) ? m : "end"
        end

        if (m = BARE_STRING_RE.match(line))
          indent = m[1]
          str    = m[2]
          start_col = indent.length
          if !protected_cols.include?(0)
            line = "#{indent}text(#{str})\n"
          end
        end

        line
      end
    end
  end
end

