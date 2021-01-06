if defined?(::Cuba)
  require 'test_helper'
  require File.expand_path(File.dirname(__FILE__) + '/../apps/cuba')
  require 'rack/test'

  class CubaTest < Minitest::Test
    include Rack::Test::Methods

    def app
      Cuba
    end

    def test_basic_get
      clear_all!

      r = get '/hello'
      assert last_response.ok?

      assert r.headers.key?("X-Instana-T")
      assert r.headers.key?("X-Instana-S")

      spans = ::Instana.processor.queued_spans
      assert_equal 1, spans.count

      first_span = spans.first
      assert_equal :rack, first_span[:n]
      assert first_span.key?(:data)
      assert first_span[:data].key?(:http)

      assert first_span[:data][:http].key?(:method)
      assert_equal "GET", first_span[:data][:http][:method]

      assert first_span[:data][:http].key?(:url)
      assert_equal "/hello", first_span[:data][:http][:url]

      assert first_span[:data][:http].key?(:status)
      assert_equal 200, first_span[:data][:http][:status]

      assert first_span[:data][:http].key?(:host)
      assert_equal "example.org", first_span[:data][:http][:host]
    end

    def test_path_template
      clear_all!

      r = get '/greet/instana'
      assert last_response.ok?

      spans = ::Instana.processor.queued_spans
      assert_equal 1, spans.count

      first_span = spans.first
      assert_equal :rack, first_span[:n]
      assert_equal '/greet/{name}', first_span[:data][:http][:path_tpl]
    end
  end
end
