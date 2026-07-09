# frozen_string_literal: true

require "http_decoy"
require "http_decoy/minitest"
require "webmock/minitest"
require "minitest/autorun"
require "net/http"
require "json"

# Allow real localhost connections (for the fake server itself).
# WebMock stubs everything else.
WebMock.disable_net_connect!(allow_localhost: true)
