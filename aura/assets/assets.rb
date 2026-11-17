require_relative "css"
require_relative "script"
require_relative "favicon"
require_relative "fingerprint"
require_relative "manifest"
require_relative "compressor"
require_relative "css_pipeline"
require_relative "css_modules"
require_relative "code_splitter"
require_relative "image_optimizer"
require_relative "fonts"
require_relative "hmr"
require_relative "bundler"
require_relative "bundle_analyzer"
require_relative "utilities"

module Aura
  module Assets

    def self.utilities
      Utilities
    end
  end
end
