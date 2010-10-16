#!/usr/bin/env wisq_utils_ruby

$LOAD_PATH << File.dirname(__FILE__) + '/../../lib'
require 'uniterm/scripting'

class Uniterm::TabClose
  include Uniterm::Scripting
  
  def run(window_id, tab_tty)
    window = select_terminal_window(window_id)
    if pid = find_shell_process(tab_tty)
      # Killing a shell causes the current terminal to adopt
      # the killed terminal's profile.  Until this is fixed,
      # we must still select_terminal_window first.
      Process.kill('TERM', pid)
    else
      select_terminal_tab(window, tab_tty)
      menu_click('Terminal', 'Shell', window.tabs.count == 1 ? 'Close Window' : 'Close Tab')
    end
  end
end

Uniterm::TabClose.new.lock_and_run(*ARGV)
