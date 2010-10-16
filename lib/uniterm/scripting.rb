#!/usr/bin/env wisq_utils_ruby

require 'rubygems'
require 'appscript'

require 'uniterm'

module Uniterm::Scripting
  include Uniterm::Common
  
  TMP_DIR   = File.dirname(__FILE__) + '/../../tmp'
  LOCK_FILE = TMP_DIR + '/uniterm.lock'

  def lock_and_run(*args)
    lock
    run(*args)
  end

  def lock
    @@uniterm_lock = File.open(LOCK_FILE, 'w')
    @@uniterm_lock.flock(File::LOCK_EX)
  end

  def menu_click(app, first, *rest)
    sys = Appscript.app.by_name('System Events.app')

    item = sys.processes[app].menu_bars[1].menus[first]

    rest.each_with_index do |names, rest_index|
      names = [*names]
      names.each_with_index do |name, names_index|
        begin
          new_item = item.menu_items[name]
          new_item = new_item.menus[name] unless rest_index >= rest.count - 1
          new_item.get
          item = new_item
          break
        rescue Appscript::CommandError => e
          raise [rest, rest_index].inspect if names_index >= names.count - 1
        end
      end
    end

    sys.click(item)
  end

  def select_terminal
    terminal.activate
  end

  def select_terminal_window(window_id)
    window = terminal.windows.ID(window_id.to_i)
    window.frontmost.set(true)
    window
  end

  def select_terminal_tab(window, tab_tty)
    tab = window.tabs[Appscript.its.tty.eq(tab_tty)].first
    tab.selected.set(true)
  end

  def find_shell_process(tty)
    base = File.basename(tty)

    uni_popen('ps') do |fh|
      fh.each_line do |line|
        if line.include?(base) && line.include?(' -sleep ')
          return line.split(' ', 2).first.to_i
        end
      end
    end

    nil
  end

  private

  def terminal
    @terminal ||= Appscript.app.by_name('Terminal.app')
  end
    
end
