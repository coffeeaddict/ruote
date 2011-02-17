#--
# Copyright (c) 2005-2011, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++


module Ruote

  #
  # The class where despatchement of workitems towards [real] participant
  # is done.
  #
  # Can be extended/replaced for better handling of Thread (why not something
  # like a thread pool or no threads at all).
  #
  class DispatchPool

    def initialize(context)

      @context = context
    end

    def handle(msg)

      case msg['action']
        when 'dispatch'
          dispatch(msg)
        when 'dispatch_cancel'
          dispatch_cancel(msg)
        else
          # simply discard the message
      end
    end

    protected

    def dispatch_cancel(msg)

      flavour = msg['flavour']

      participant = @context.plist.instantiate(msg['participant'])

      begin
        participant.cancel(Ruote::FlowExpressionId.new(msg['fei']), flavour)
      rescue Exception => e
        raise(e) if flavour != 'kill'
      end

      @context.storage.put_msg(
        'reply',
        'fei' => msg['fei'],
        'workitem' => msg['workitem'])
    end

    def dispatch(msg)

      participant = @context.plist.lookup(
        msg['participant'] || msg['participant_name'], msg['workitem'])

      if do_not_thread(participant, msg)
        do_dispatch(participant, msg)
      else
        do_threaded_dispatch(participant, msg)
      end
    end

    # The actual dispatching (call to Participant#consume).
    #
    def do_dispatch(participant, msg)

      workitem = Ruote::Workitem.new(msg['workitem'])

      workitem.fields['dispatched_at'] = Ruote.now_to_utc_s

      participant.consume(workitem)

      @context.storage.put_msg(
        'dispatched',
        'fei' => msg['fei'],
        'participant_name' => workitem.participant_name)
          # once the consume is done, asynchronously flag the
          # participant expression as 'dispatched'
    end

    # Wraps the call to do_dispatch in a thread.
    #
    def do_threaded_dispatch(participant, msg)

      msg = Rufus::Json.dup(msg)
        #
        # the thread gets its own copy of the message
        # (especially important if the main thread does something with
        # the message 'during' the dispatch)

      # Maybe at some point a limit on the number of dispatch threads
      # would be OK.
      # Or maybe it's the job of an extension / subclass

      Thread.new do
        begin

          do_dispatch(participant, msg)

        rescue Exception => exception
          @context.error_handler.msg_handle(msg, exception)
        end
      end
    end

    # Returns true if the participant doesn't want the #consume to happen
    # in a new Thread.
    #
    def do_not_thread(participant, msg)

      return false unless participant.respond_to?(:do_not_thread)

      if participant.method(:do_not_thread).arity == 0
        participant.do_not_thread
      else
        participant.do_not_thread(Ruote::Workitem.new(msg['workitem']))
      end
    end
  end
end

