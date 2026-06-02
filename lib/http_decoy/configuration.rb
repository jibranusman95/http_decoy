# frozen_string_literal: true

module HttpDecoy
  class Configuration
    attr_accessor :auto_intercept

    def initialize
      @auto_intercept = true
    end
  end
end
