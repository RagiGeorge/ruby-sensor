require 'test_helper'

class SidekiqClientTest < Minitest::Test
  def test_config_defaults
    assert ::Instana.config[:sidekiq_client].is_a?(Hash)
    assert ::Instana.config[:sidekiq_client].key?(:enabled)
    assert_equal true, ::Instana.config[:sidekiq_client][:enabled]
  end

  def test_enqueue
    clear_all!

    Instana.tracer.start_or_continue_trace(:sidekiqtests) do
      ::Sidekiq::Client.push(
        'queue' => 'some_random_queue',
        'class' => ::SidekiqJobOne,
        'args' => [1, 2, 3],
        'retry' => false
      )
    end

    queue = ::Sidekiq::Queue.new('some_random_queue')
    job = queue.first

    assert_job_enqueued(job)
    assert_normal_trace_recorded(job)
  end

  def test_enqueue_failure
    clear_all!

    Instana.tracer.start_or_continue_trace(:sidekiqtests) do
      add_sidekiq_exception_middleware
      begin
        ::Sidekiq::Client.push(
          'queue' => 'some_random_queue',
          'class' => ::SidekiqJobTwo,
          'args' => [1, 2, 3],
          'retry' => false
        )
      rescue; end
      remove_sidekiq_exception_middleware
    end

    queue = ::Sidekiq::Queue.new('some_random_queue')
    assert_equal 0, queue.size

    assert_failure_trace_recorded
  end

  private

  def assert_job_enqueued(job)
    job_message = JSON.parse(job.value)

    assert_equal 'some_random_queue', job_message['queue']
    assert_equal 'SidekiqJobOne', job_message['class']
    assert_equal [1, 2, 3], job_message['args']
    assert_equal false, job_message['retry']
    assert_equal false, job_message['X-Instana-T'].nil?
    assert_equal false, job_message['X-Instana-S'].nil?
  end

  def assert_normal_trace_recorded(job)
    assert_equal 1, ::Instana.processor.queue_count
    client_trace = Instana.processor.queued_traces.first

    assert_equal 2, client_trace.spans.count
    spans = client_trace.spans.to_a
    first_span = spans[0]
    second_span = spans[1]

    assert_equal :sdk, first_span[:n]
    assert_equal :sidekiqtests, first_span[:data][:sdk][:name]

    assert_equal first_span.id, second_span[:p]

    assert_equal :sdk, second_span[:n]
    data = second_span[:data][:sdk]

    assert_equal :sidekiqclient, data[:name]
    assert_equal 'some_random_queue', data[:custom][:sidekiqclient][:queue]
    assert_equal 'SidekiqJobOne', data[:custom][:sidekiqclient][:job]
    assert_equal false, data[:custom][:sidekiqclient][:retry]
    assert_equal job['jid'], data[:custom][:sidekiqclient][:job_id]
  end

  def assert_failure_trace_recorded
    assert_equal 1, ::Instana.processor.queue_count
    client_trace = Instana.processor.queued_traces.first

    assert_equal 2, client_trace.spans.count
    spans = client_trace.spans.to_a
    first_span = spans[0]
    second_span = spans[1]

    assert_equal :sdk, first_span[:n]
    assert_equal :sidekiqtests, first_span[:data][:sdk][:name]

    assert_equal first_span.id, second_span[:p]

    assert_equal :sdk, second_span[:n]
    assert_equal true, second_span[:error]
    assert_equal false, second_span[:stack].nil?


    data = second_span[:data][:sdk]

    assert_equal :sidekiqclient, data[:name]
    assert_equal 'some_random_queue', data[:custom][:sidekiqclient][:queue]
    assert_equal 'SidekiqJobTwo', data[:custom][:sidekiqclient][:job]
    assert_equal false, data[:custom][:sidekiqclient][:retry]
    assert_equal 'Fail to enqueue job', data[:custom][:log][:message]
  end

  SidekiqMiddlewareException = Class.new do
    def call(*_args)
      raise 'Fail to enqueue job'
    end
  end

  def add_sidekiq_exception_middleware
    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.add SidekiqMiddlewareException
      end
    end
  end

  def remove_sidekiq_exception_middleware
    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.remove SidekiqMiddlewareException
      end
    end
  end
end
