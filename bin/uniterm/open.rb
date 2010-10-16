#!/usr/bin/env wisq_utils_ruby

$LOAD_PATH << File.dirname(__FILE__) + '/../../lib'
require 'uniterm/scripting'

class Uniterm::TabOpen
  include Uniterm::Scripting

  def run(theme_name, tab_title, window_id)
    window_id = window_id.to_i

    @terminal = Appscript.app.by_name('Terminal.app')
    @terminal.activate

    if window_id > 0
      window = @terminal.windows.ID(window_id)
      window.frontmost.set(true)
      open_tab(theme_name, 'New Tab')
    else
      open_tab(theme_name, 'New Window')
    end

    window = @terminal.windows[Appscript.its.frontmost.eq(true)]
    tab = window.selected_tab

    tty = tab.tty.get.first
    File.open(tty, 'w') do |fh|
      fh.print "\033]2;#{tab_title}\007"
      fh.flush
    end

    output = [window.id_.get, tty]
    puts output.join(':')
  end

  private

  def open_tab(theme_name, open_type)
    menu_click('Terminal', 'Shell', open_type, [theme_name, 'Uniterm'])
  end
end

Uniterm::TabOpen.new.lock_and_run(*ARGV)
