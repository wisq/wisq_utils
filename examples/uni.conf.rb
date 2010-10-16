# Sample verbose configuration file for Unicorn (not Rack)
#
# This configuration file documents many features of Unicorn
# that may not be needed for some applications. See
# http://unicorn.bogomips.org/examples/unicorn.conf.minimal.rb
# for a much simpler configuration file.
#
# See http://unicorn.bogomips.org/Unicorn/Configurator.html for complete
# documentation.

# UNITERM USERS: Uncomment the following.  See the "UNITERM" file.
#
# if uni = ENV['UNI_LIB_PATH']
#   $LOAD_PATH << uni
#   require 'uniterm/config'
# end

# Use at least one worker per core if you're on a dedicated server,
# more will usually help for _short_ waits on databases/caches.
worker_processes 4
# (required by uni)

# Help ensure your application will always spawn in the symlinked
# "current" directory that Capistrano sets up.
my_work_dir = ENV['HOME'] + '/path/to/project'
working_directory my_work_dir # available in 0.94.0+
# (Required by uni.  I use a variable here for convenience later.)

# You can listen on both a Unix domain socket and a TCP port.
# Unix socket can use a shorter backlog for quicker failover when busy.
#listen "/tmp/.sock", :backlog => 64
listen '127.0.0.1:3000', :tcp_nopush => true
# (Required by uni, but it will only use the LAST "listen" command.)

# Nuke workers after 30 seconds instead of 60 seconds (the default).
if defined?(Uniterm)
  timeout 300 # don't interrupt debugging
else
  timeout 30
end

# PID file.
pid ENV['PIDFILE']
# (required by uni, and should not be changed)

# By default, the Unicorn logger will write to stderr.
# Additionally, ome applications/frameworks log to stderr or stdout,
# so prevent them from going to /dev/null when daemonized here:
#stderr_path "/path/to/app/shared/log/unicorn.stderr.log"
#stdout_path "/path/to/app/shared/log/unicorn.stdout.log"
stderr_path "/dev/stderr"
stdout_path "/dev/stdout"
# (this will provide debug output directly to the console)

# combine REE with "preload_app true" for memory savings
# http://rubyenterpriseedition.com/faq.html#adapt_apps_for_cow
devel = my_work_dir + '/config/environments/development.rb'
File.open(devel) do |fh|
  fh.each_line do |line|
    if line =~ /^config\.cache_classes\s*=\s*(true|false)/
      preload_app($1 == 'true')
      break
    end
  end
end
# You can also just use
#   preload_app true/false
# but I prefer to autodetect straight from my Rails environment file.

GC.respond_to?(:copy_on_write_friendly=) and GC.copy_on_write_friendly = true

before_fork do |server, worker|
  defined?(Uniterm) and Uniterm::Config.before_fork(server, worker)

  # the following is highly recomended for Rails + "preload_app true"
  # as there's no need for the master process to hold a connection
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!

  # The following is only recommended for memory/DB-constrained
  # installations.  It is not needed if your system can house
  # twice as many worker_processes as you have configured.
  #
  # # This allows a new master process to incrementally
  # # phase out the old master process with SIGTTOU to avoid a
  # # thundering herd (especially in the "preload_app false" case)
  # # when doing a transparent upgrade.  The last worker spawned
  # # will then kill off the old master process with a SIGQUIT.
  # old_pid = "#{server.config[:pid]}.oldbin"
  # if old_pid != server.pid
  #   begin
  #     sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
  #     Process.kill(sig, File.read(old_pid).to_i)
  #   rescue Errno::ENOENT, Errno::ESRCH
  #   end
  # end
  #
  # # *optionally* throttle the master from forking too quickly by sleeping
  # sleep 1
end

after_fork do |server, worker|
  defined?(Uniterm) and Uniterm::Config.after_fork(server, worker)

  # per-process listener ports for debugging/admin/migrations
  # addr = "127.0.0.1:#{9293 + worker.nr}"
  # server.listen(addr, :tries => -1, :delay => 5, :tcp_nopush => true)

  # the following is *required* for Rails + "preload_app true",
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection

  # if preload_app is true, then you may also want to check and
  # restart any other shared sockets/descriptors such as Memcached,
  # and Redis.  TokyoCabinet file handles are safe to reuse
  # between any number of forked children (assuming your kernel
  # correctly implements pread()/pwrite() system calls)
end

defined?(Uniterm) and Uniterm::Config.after_config
