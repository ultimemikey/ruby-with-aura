require "set"

module Aura
  module Security

    class CapabilityContext
      attr_reader :allowed_tags, :allowed_actions, :allowed_constants

      def initialize(tags: [], actions: [], constants: {})
        @allowed_tags = ::Set.new(tags.map(&:to_s))
        @allowed_actions = ::Set.new(actions.map(&:to_sym))
        @allowed_constants = ::Hash[constants.map { |k, v| [k.to_s, v] }]
      end

      def allowed_tag?(tag)
        @allowed_tags.include?(tag.to_s)
      end

      def allowed_action?(action)
        @allowed_actions.include?(action.to_sym)
      end

      def resolve_constant(name)
        resolver = @allowed_constants[name.to_s]
        if resolver.nil?
          ::Kernel.raise ::SecurityError,
            "[Aura Security] Scoped Constant `#{name}` is not accessible in this context. " \
            "Allowed constants: #{@allowed_constants.keys.join(', ')}"
        end
        resolver.respond_to?(:call) ? resolver.call : resolver
      end

      def self.default
        new(
          tags: default_tags,
          actions: default_actions,
          constants: default_constants
        )
      end

      def self.default_tags

        %w[
          html head body header footer main nav aside section article div
          h1 h2 h3 h4 h5 h6 p span strong em mark small code pre kbd
          samp var abbr cite del ins sub sup time blockquote address
          ul ol li dl dt dd form label input textarea select option
          button fieldset legend output progress meter table thead tbody
          tfoot tr th td caption colgroup col img video audio source
          picture figure figcaption iframe details summary dialog a link
          hr br wbr data canvas svg fragment
        ]
      end

      def self.default_actions
        %i[
          title lang meta seo asset css script favicon render fragment
          text slot layout use include define component on public_on
          field submit aria cookie store p select link open
          state computed get set show unless_ each bind effect
          loader data revalidate validate errors error_for t locale
          on_error on_unmount static_
        ]
      end

      def self.default_constants
        {
          "RUBY_VERSION"  => -> { ::RUBY_VERSION },
          "AURA_VERSION"  => -> { "1.0" },
          "TRUE"          => -> { true },
          "FALSE"         => -> { false },
          "NIL"           => -> { nil }
        }
      end
    end
  end
end
