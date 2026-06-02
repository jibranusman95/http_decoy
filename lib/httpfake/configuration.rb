# frozen_string_literal: true

module HttpFake
  class Configuration
    attr_accessor :auto_intercept

    def initialize
      @auto_intercept = true
    end
  end
end
