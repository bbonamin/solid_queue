require "test_helper"
require "active_support/testing/method_call_assertions"

class DispatcherTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::MethodCallAssertions

  setup do
    @dispatcher = SolidQueue::Dispatcher.new(polling_interval: 0.1, batch_size: 10)
  end

  teardown do
    @dispatcher.stop
  end

  test "dispatcher is registered as process" do
    @dispatcher.start
    wait_for_registered_processes(1, timeout: 1.second)

    process = SolidQueue::Process.first
    assert_equal "Dispatcher", process.kind
    assert_equal({ "polling_interval" => 0.1, "batch_size" => 10, "concurrency_maintenance_interval" => 600 }, process.metadata)
  end

  test "concurrency maintenance is optional" do
    no_concurrency_maintenance_dispatcher = SolidQueue::Dispatcher.new(polling_interval: 0.1, batch_size: 10, concurrency_maintenance: false)
    no_concurrency_maintenance_dispatcher.start

    wait_for_registered_processes(1, timeout: 1.second)

    process = SolidQueue::Process.first
    assert_equal "Dispatcher", process.kind
    assert_equal({ "polling_interval" => 0.1, "batch_size" => 10 }, process.metadata)

    no_concurrency_maintenance_dispatcher.stop
  end

  test "recurring schedule" do
    recurring_task = { example_task: { class: "AddToBufferJob", schedule: "every hour", args: 42 } }
    with_recurring_schedule = SolidQueue::Dispatcher.new(concurrency_maintenance: false, recurring_tasks: recurring_task)

    with_recurring_schedule.start

    wait_for_registered_processes(1, timeout: 1.second)

    process = SolidQueue::Process.first
    assert_equal "Dispatcher", process.kind
    assert_equal [ "AddToBufferJob.perform_later(42) [ 0 * * * * ]" ], process.metadata["recurring_schedule"]

    with_recurring_schedule.stop
  end

  test "polling queries are logged" do
    log = StringIO.new
    old_logger, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(log)
    old_silence_polling, SolidQueue.silence_polling = SolidQueue.silence_polling, false

    @dispatcher.start
    sleep 0.5

    assert_match /SELECT .* FROM .solid_queue_scheduled_executions. WHERE/, log.string
  ensure
    ActiveRecord::Base.logger = old_logger
    SolidQueue.silence_polling = old_silence_polling
  end

  test "polling queries can be silenced" do
    log = StringIO.new
    old_logger, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(log)
    old_silence_polling, SolidQueue.silence_polling = SolidQueue.silence_polling, true

    @dispatcher.start
    sleep 0.5

    assert_no_match /SELECT .* FROM .solid_queue_scheduled_executions. WHERE/, log.string
  ensure
    ActiveRecord::Base.logger = old_logger
    SolidQueue.silence_polling = old_silence_polling
  end

  test "run more than one instance of the dispatcher" do
    15.times do
      AddToBufferJob.set(wait: 0.2).perform_later("I'm scheduled")
    end
    assert_equal 15, SolidQueue::ScheduledExecution.count

    another_dispatcher = SolidQueue::Dispatcher.new(polling_interval: 0.1, batch_size: 10)
    @dispatcher.start
    another_dispatcher.start

    sleep 0.5

    assert_equal 0, SolidQueue::ScheduledExecution.count
    assert_equal 15, SolidQueue::ReadyExecution.count

    another_dispatcher.stop
  end
end
