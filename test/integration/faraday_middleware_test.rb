require "integration_helper"
require "typhoeus/adapters/faraday"

class Circuitbox
  class FaradayMiddlewareTest < Minitest::Test
    @@only_once = false
    def setup
      @connection = Faraday.new do |c|
        c.use FaradayMiddleware
        c.adapter :typhoeus # support in_parallel
      end
      @success_url = "http://localhost:4711"
      @failure_url = "http://localhost:4712"

      if !@@only_once
        FakeServer.create(4711, ['200', {'Content-Type' => 'text/plain'}, ["Success!"]])
        FakeServer.create(4712, ['500', {'Content-Type' => 'text/plain'}, ["Failure!"]])
      end
    end

    def teardown
      Circuitbox.reset
    end

    def test_failure_circuit_response
      failure_response = @connection.get(@failure_url)
      assert_equal failure_response.status, 503
      assert_match failure_response.original_response.body, "Failure!"
    end

    def test_open_circuit_response
      10.times { @connection.get(@failure_url) } # make the CircuitBreaker open

      open_circuit_response = @connection.get(@failure_url)
      assert_equal open_circuit_response.status, 503
      assert open_circuit_response.original_response.nil?
    end

    def test_closed_circuit_response
      result = @connection.get(@success_url)
      assert result.success?
    end

    def test_parallel_requests_closed_circuit_response
      response_1, response_2 = nil
      @connection.in_parallel do
        response_1 = @connection.get(@success_url)
        response_2 = @connection.get(@success_url)
      end

      assert response_1.success?
      assert response_2.success?
    end

    def test_parallel_requests_open_circuit_response
      10.times { @connection.get(@failure_url) } # make the CircuitBreaker open
      response_1, response_2 = nil
      @connection.in_parallel do
        response_1 = @connection.get(@failure_url)
        response_2 = @connection.get(@failure_url)
      end

      assert_equal response_1.status, 503
      assert_equal response_2.status, 503
    end

  end
end
