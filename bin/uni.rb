#!/usr/bin/ruby

#
# This script is designed to facilitate launching, restarting, and shutting
# down Unicorn instances for local development, typically taking the place
# of "script/server" or "rails server" for Rails projects.
#
# Usage: unicorn <name> [down]
#
#   Each Unicorn instance requires its own configuration file, stored in
#   "$HOME/.uni/conf" with the format "<name>.conf.rb".
#
#   The recommended usage is to create a "uni" symlink somewhere in
#   your $PATH that links to this file.  You can then call it from anywhere,
#   and it will change to the correct directory automatically.
#
#   Once set up, you can call "uni <name>" to start or restart an instance,
#   or "uni <name> down" to shut it down.
#
# Restarting:
#
#   uni automatically chooses between a quick restart (SIGHUP) or a
#   full restart (SIGUSR2) based on the "preload_app" setting.
#   Both approaches should provide a seamless rolling restart.
#
# Required configuration parameters:
#   (You _must_ specify these in the config, even if you use the default!)
#
#   working_directory
#     uni will chdir to this directory before running Unicorn.
#
#   preload_app
#     If true, uni must perform a full restart, since the application code
#     is only loaded at Unicorn start.  Otherwise, uni can perform a quick
#     restart, since each worker will re-read the application code.
#
#   worker_processes
#     uni uses this number to verify that all workers have been launched.
#
#   listen
#     uni will connect to this port to ensure that new workers are
#     receiving connections before it terminates the old workers.
#
#   pid
#     Should always be set to "ENV['PIDFILE']".  Variable supplied by uni.
#
# Example config:
#
#   An example configuration file is available as examples/uni.conf.rb.
#

require 'pathname'
require 'digest/md5'
require 'yaml'
require 'socket'

class Uni
  HOME_DIR = Pathname.new(ENV['HOME'])

  UNI_PATH     = HOME_DIR + '.uni'
  CONFIG_PATH  = UNI_PATH + 'conf'
  RUN_PATH     = UNI_PATH + 'run'

  attr_reader :name

  def initialize(name)
    @name = name
  end

  def launch
    if pid = find_unicorn_process
      restart(pid)
    else
      run
    end
  end

  def shutdown
    unless pid = find_unicorn_process
      puts "No '#{name}' unicorn is running."
      exit(1)
    end

    puts "Sending shutdown signal to Unicorn (PID #{pid})."
    Process.kill('QUIT', pid)

    wait(30, 'Waiting for process to exit') do
      find_unicorn_process.nil?
    end

    puts
    puts "Unicorn has shut down."
  end

  private


  ### Basic actions

  def run
    work_dir = Pathname.new(config.working_directory)

    make_run_path
    ENV['PIDFILE'] = pid_file
    ENV['UNI_LIB_PATH'] = Pathname.new(__FILE__).realpath.dirname + '../lib'
    ENV['UNI_CONFIG_NAME'] = @name
    save_config

    Dir.chdir(work_dir)
    exec('bundle', 'exec', 'unicorn', '-D', '-c', config_file.to_s)
    raise 'exec failed'
  end

  def restart(pid)
    if (old_config || config).preload_app
      restart_full(pid)
      puts
      puts "READY: Full restart complete."
    else
      restart_quick(pid)
      puts
      puts "READY: Quick restart complete."
    end
  end


  ### Restart methods ###

  def restart_quick(pid)
    old_workers = get_worker_pids(pid)

    puts "Sending restart signal to existing Unicorn (PID #{pid})."
    Process.kill('HUP', pid)
    save_config

    expect = config.worker_processes.to_i
    new_workers = nil
    wait(workers_timeout, 'Waiting for workers') do
      new_workers = get_worker_pids(pid) - old_workers
      new_workers.count >= expect
    end

    host, port = config.listen.split(':')
    wait(connect_timeout, 'Waiting for a new worker connection') do
      test_connection(host, port, new_workers)
    end
  end

  def restart_full(old_pid)
    puts "Sending launch signal to existing Unicorn (PID #{old_pid})."
    Process.kill('USR2', old_pid)

    new_pid = wait(10, 'Waiting for new process') do
      find_unicorn_process(old_pid)
    end

    puts "New Unicorn launched: #{new_pid}"

    begin
      expect = config.worker_processes.to_i
      worker_pids = nil
      wait(workers_timeout, 'Waiting for workers') do
        if find_unicorn_process(new_pid) == old_pid
          puts ' (died)'
          return restart_full_abort(old_pid)
        end

        worker_pids = get_worker_pids(new_pid)
        worker_pids.count >= expect
      end

      puts "Shutting down workers for old Unicorn."
      Process.kill('WINCH', old_pid)

      host, port = config.listen.split(':')
      wait(connect_timeout, 'Waiting for a new worker connection') do
        test_connection(host, port, worker_pids)
      end

      puts "Shutting down old Unicorn."
      Process.kill('QUIT', old_pid)
      save_config
    rescue TimeoutError
      puts "Shutting down new Unicorn."
      Process.kill('QUIT', new_pid)

      restart_full_abort(old_pid)
    end
  end

  def restart_full_abort(pid)
    restart_quick(pid)

    puts
    puts "FAILED: Unicorn rolled back."
    exit(1)
  end


  ### UI functions ###

  def wait(secs, status)
    retval = yield
    return retval if retval

    print "#{status}: "
    $stdout.flush

    1.upto(secs).each do
      sleep(1)
      print '.'
      $stdout.flush

      if retval = yield
        puts
        return retval
      end
    end

    puts ' (timeout)'
    raise TimeoutError
  end


  ### Unicorn utility functions ###

  def find_unicorn_process(reject = nil)
    pid = begin
      pid_file.read.to_i
    rescue Errno::ENOENT
      return nil
    end

    pid = pid_file.read.to_i
    if pid > 0 && pid != reject
      process_list do |l_pid, command|
        next unless pid == l_pid
        return command =~ /unicorn/ ? pid : nil
      end
    end

    nil
  end

  def get_worker_pids(pid)
    pids = []
    run_command('pstree', pid) do |fh|
      fh.each_line do |line|
        pids << $1.to_i if line =~ /^\s[|\\]--- (\d+) /
      end
    end
    pids
  end

  def test_connection(host, port, pids)
    sock = TCPSocket.open(host, port)
    my_port = Socket.unpack_sockaddr_in(sock.getsockname).first

    begin
      run_command('lsof', '-i', ":#{my_port}") do |fh|
        fh.each_line do |line|
          return true if line =~ /^ruby\s*(\d+)\s/ && pids.include?($1.to_i)
        end
      end
    ensure
      sock.close
    end

    false
  end


  ### Generic utility functions ###

  def run_command(*command)
    IO.popen('-') do |fh|
      if fh.nil? # child
        exec(*command.map(&:to_s))
        Kernel.exit!(1)
      else # server
        yield(fh)
      end
    end
  end

  def capture_command(*command)
    output = ''
    run_command(*command) do |fh|
      output = fh.read.lines.to_a
    end

    raise 'Cannot find start of capture data' unless index = output.index("CAPTURE\n")
    output.drop(index).join
  end

  def process_list
    run_command('ps', 'x', '-o', 'pid,command') do |fh|
      fh.each_line do |line|
        pid = line.slice!(0, 5).strip.to_i
        command = line.chomp.strip
        yield [pid, command]
      end
    end
  end


  ### Config management ###

  def config
    @config ||= load_config
  end

  def old_config
    @old_config ||= load_old_config
  end

  def load_config
    raise "Configuration not found: '#{name}'" unless config_file.exist?

    loader = Loader.new
    loader.load(config_file)
    Config.new(loader.data)
  end

  def load_old_config
    if @old_config_missing
      nil
    elsif old_config_file.exist?
      Config.new(YAML.load(old_config_file.read))
    else
      @old_config_missing = true
      nil
    end
  end

  def save_config
    File.open(old_config_file, 'w') do |fh|
      fh.puts config.data.to_yaml
    end
  end


  ### Filenames ###

  def config_file
    CONFIG_PATH + "#{name}.conf.rb"
  end
  def old_config_file
    RUN_PATH + "#{name}.yml"
  end
  def pid_file
    RUN_PATH + "#{name}.pid"
  end

  def make_run_path
    RUN_PATH.mkdir unless RUN_PATH.directory?
  end

  ### Timeouts ###

  def workers_timeout
    config.preload_app ? 60 : 20
  end
  def connect_timeout
    config.preload_app ? 20 : 60
  end


  ### Support classes ###

  class TimeoutError < StandardError; end

  class Loader
    attr_reader :data

    def initialize
      @data = {}
    end

    def load(file)
      ENV.delete('UNI_LIB_PATH')
      eval(File.read(file))
    end

    def method_missing(name, *args)
      @data[name] = args.first
    end
  end

  class Config
    attr_reader :data

    def initialize(data)
      @data = data
    end

    def method_missing(name, *args)
      raise "Config parameter not found: #{name}" unless @data.has_key?(name)
      @data[name]
    end
  end

end

uni = Uni.new(ARGV.shift)
if ARGV.first == 'down'
  uni.shutdown
else
  uni.launch
end
