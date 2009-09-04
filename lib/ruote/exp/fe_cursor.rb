#--
# Copyright (c) 2005-2009, John Mettraux, jmettraux@gmail.com
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


require 'ruote/exp/flowexpression'
require 'ruote/exp/command'


module Ruote::Exp

  #
  # This class implements the 'cursor' and the 'repeat' (loop) expressions.
  #
  # The cursor expression is a kind of enhanced 'sequence'. Like a sequence
  # it will execute its child expression one by one, sequentially. Unlike a
  # sequence though, it will obey 'commands'.
  #
  #   cursor do
  #     author
  #     reviewer
  #     rewind :if => '${f:not_ok}'
  #     publisher
  #   end
  #
  # In this simplistic example, the process will flow from author to reviewer
  # and back until the reviewer sets the workitem field 'not_ok' to something
  # else than the value 'true'.
  #
  # There are two ways to pass commands to a cursor either directly from
  # the process definition with a cursor command expression, either via
  # the workitem '__command__' [special] field.
  #
  # == cursor commands
  #
  # The commands that a cursor understands are listed here. The most powerful
  # ones are 'rewind' and 'jump'.
  #
  # === rewind
  #
  # Rewinds the cursor up to its first child expression.
  #
  #   cursor do
  #     author
  #     reviewer
  #     rewind :if => '${f:not_ok}'
  #     publisher
  #   end
  #
  # === break
  #
  # Exits the cursor.
  #
  #   cursor do
  #     author
  #     reviewer
  #     rewind :if => '${f:review} == fix'
  #     break :if => '${f:review} == abort'
  #     publisher
  #   end
  #
  # === skip & back
  #
  # Those two commands jump forth and back respectively. By default, they
  # skip 1 child, but they accept a numeric parameter holding the number
  # of children to skip.
  #
  #   cursor do
  #     author
  #     reviewer
  #     rewind :if => '${f:review} == fix'
  #     skip 2 :if => '${f:reviwer} == 'publish'
  #     reviewer2
  #     rewind :if => '${f:review} == fix'
  #     publisher
  #   end
  #
  # === jump
  #
  # Jump is probably the most powerful of the cursor commands. It allows to
  # jump to a specified expression that is a direct child of the cursor.
  #
  #   cursor do
  #     author
  #     reviewer
  #     jump :to => 'author', :if => '${f:review} == fix'
  #     jump :to => 'publisher', :if => '${f:review} == publish'
  #     reviewer2
  #     jump :to => 'author', :if => '${f:review} == fix'
  #     publisher
  #   end
  #
  # Note that the :to accepts the name of an expression or the value of
  # its :ref attribute or the value of its :tag attribute.
  #
  #   cursor do
  #     participant :ref => 'author'
  #     participant :ref => 'reviewer'
  #     jump :to => 'author', :if => '${f:review} == fix'
  #     participant :ref => 'publisher'
  #   end
  #
  # == repeat (loop)
  #
  # A 'cursor' expression exits implicitely as soon as its last child replies
  # to it.
  # a 'repeat' expression will apply (again) the first child after the last
  # child replied. A 'break' cursor command might be necessary to exit the loop
  # (or a cancel_process, but that exits the whole process instance).
  #
  #   sequence do
  #     repeat do
  #       author
  #       reviewer
  #       break :if => '${f:review} == ok'
  #     end
  #     publisher
  #   end
  #
  class CursorExpression < FlowExpression

    include CommandMixin

    names :cursor, :loop, :repeat

    def apply

      reply(@applied_workitem)
    end

    def reply (workitem)

      position = workitem.fei == self.fei ? -1 : workitem.fei.child_id
      position += 1

      com, arg = get_command(workitem)

      return reply_to_parent(workitem) if com == 'break'

      case com
      when 'rewind', 'continue' then position = 0
      when 'skip' then position += arg
      when 'jump' then position = jump_to(workitem, position, arg)
      end

      position = 0 if position >= tree_children.size && is_loop?

      if position < tree_children.size
        apply_child(position, workitem)
      else
        reply_to_parent(workitem)
      end
    end

    protected

    def is_loop?

      name == 'loop' || name == 'repeat'
    end

    # Jumps to an integer position, or the name of an expression
    # or a tag name of a ref name.
    #
    def jump_to (workitem, position, arg)

      pos = Integer(arg) rescue nil

      return pos if pos != nil

      tree_children.each_with_index do |c, i|

        exp_name = c[0]
        ref = c[1]['ref']
        tag = c[1]['tag']

        ref = Ruote.dosub(ref, self, workitem) if ref
        tag = Ruote.dosub(tag, self, workitem) if tag

        next if exp_name != arg && ref != arg && tag != arg

        pos = i
        break
      end

      pos ? pos : position
    end
  end
end
