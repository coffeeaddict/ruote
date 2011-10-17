
#
# testing ruote
#
# Mon Oct 17 09:47:52 JST 2011
#

require File.expand_path('../base', __FILE__)


class FtRetriesTest < Test::Unit::TestCase
  include FunctionalBase

  class BadParticipant
    include Ruote::LocalParticipant
    def on_workitem
      fail 'badly'
    end
    def on_cancel
    end
  end

  #
  # :on_error => '4s: retry'

  def test_single_retry

    @dashboard.register_participant :alpha, BadParticipant

    pdef = Ruote.process_definition do
      alpha :on_error => '4s: retry'
    end

    #@dashboard.noisy = true

    wfid = @dashboard.launch(pdef)

    @dashboard.wait_for('fail')

    alpha = @dashboard.ps(wfid).expressions.last

    assert_not_nil alpha.h.timers
    assert_equal '', alpha.tree[1]['on_error']

    @dashboard.wait_for('error_intercepted')

    ps = @dashboard.ps(wfid)

    assert_equal '#<RuntimeError: badly>', ps.errors.first.message
  end

  #
  # :on_error => '4x: retry'

  def test_bad_time_syntax

    @dashboard.register_participant :alpha, BadParticipant

    pdef = Ruote.process_definition do
      alpha :on_error => '4x: retry'
    end

    #@dashboard.noisy = true

    wfid = @dashboard.launch(pdef)

    @dashboard.wait_for('error_intercepted')

    assert_equal(
      "#<Ruote::MetaError: schedule_retries: unknown time char 'x'>",
      @dashboard.ps(wfid).errors.first.message)
  end

  #
  # :on_error => '2s: retry, pass'

  def test_retry_then_pass

    @dashboard.register_participant :alpha, BadParticipant

    pdef = Ruote.process_definition do
      alpha :on_error => '1s: retry, pass'
      echo 'over.'
    end

    #@dashboard.noisy = true

    wfid = @dashboard.launch(pdef)

    @dashboard.wait_for('terminated')

    actions = @dashboard.context.logger.log.collect { |m|
      m['action']
    }.group_by { |a|
      a
    }

    assert_equal 1, actions['cancel'].size
    assert_equal 2, actions['fail'].size

    assert_equal 'over.', @tracer.to_s
  end
end

