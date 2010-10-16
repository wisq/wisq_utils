require 'uniterm'

class Uniterm::Config
  class << self
    include Uniterm::Common
  end
  
  UNITERM_BIN   = File.dirname(__FILE__) + '/../../bin/uniterm/'
  UNITERM_THEME = 'Uni-' + ENV['UNI_CONFIG_NAME']

  @@window_id  = ENV['UNITERM_WINDOW_ID']
  @@generation = ENV['UNITERM_GENERATION'].to_i
  @@tty = nil

  def self.after_config
    @@worker_num = -1

    if ENV['UNITERM_MASTER_PID'].to_i != Process.pid
      ENV['UNITERM_GENERATION'] = (@@generation += 1).to_s
      output_to_tab(generation('master'))
      ENV['UNITERM_MASTER_PID'] = Process.pid.to_s
    end
  end
  
  def self.before_fork(server, worker)
    sleep(0.3) # so tabs usually load in order
  end
  
  def self.after_fork(server, worker)
    output_to_tab(generation(worker.nr))

    if Kernel.respond_to?(:debugger) && !Kernel.respond_to?(:uniterm_debugger_old)
      Kernel.send(:alias_method, :uniterm_debugger_old, :debugger)
      Kernel.send(:alias_method, :debugger, :uniterm_debugger_new)
    end
  end

  def self.generation(title)
    t = title.to_s
    t += "-#{@@generation}" if @@generation > 1
    t
  end

  def self.output_to_tab(tab_title)
    window_id, tty = open_tab(tab_title, @@window_id)
    if @window_id.nil?
      @@window_id = window_id.to_i
      ENV['UNITERM_WINDOW_ID'] = window_id
    end

    output_to(tty)
    @@tty = tty

    at_exit { close_tab }
  end

  def self.close_tab
    fork { uni_exec(UNITERM_BIN + 'close.rb', @@window_id, @@tty) } if @@tty
    output_to('/dev/null')
    @@tty = nil
  end

  def self.select_tab
    fork { uni_exec(UNITERM_BIN + 'select.rb', @@window_id, @@tty) }
  end

  def self.output_to(dev)
    $stdout.reopen(dev, 'w')
    $stderr.reopen(dev, 'w')
    $stdin.reopen(dev, 'r')
  end

  def self.open_tab(tab_title, window_id)
    uni_popen(UNITERM_BIN + 'open.rb', UNITERM_THEME, tab_title, window_id).chomp.split(':')
  end
end

module Kernel
  def uniterm_debugger_new(*args)
    Uniterm::Config.select_tab
    uniterm_debugger_old(*args)
  end
end
