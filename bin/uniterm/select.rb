#!/usr/bin/env wisq_utils_ruby

$LOAD_PATH << File.dirname(__FILE__) + '/../../lib'
require 'uniterm/scripting'

class Uniterm::TabSelect
  include Uniterm::Scripting
  
  def run(window_id, tab_tty)
    window = select_terminal_window(window_id)
    select_terminal_tab(window, tab_tty)
    select_terminal
  end
end

Uniterm::TabSelect.new.lock_and_run(*ARGV)
