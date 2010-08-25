#!/usr/bin/env wisq_utils_ruby

#
# This script will take all your changes since a particular git reference
# point, unapply them, and reapply them with hard tabs converted to soft tabs
# (spaces).
#
# It's highly recommended you run this on a clean tree so you can isolate and
# revert the changes if you don't like them.  The script will normally abort
# if the git tree is not clean.
#
# Usage: tabify [option ...] [git-diff arg ...]
#
# Options:
#   -f   Run even if there are uncommitted changes.
#   -##  Specify soft tab width.  Default is 2 spaces.
#
# Examples:
#
#   tabify master
#     Remove tabs for changes compared against branch "master", e.g. on your
#     topic branch.
#
#   tabify master some/file.js another/file.rb
#     Same as above, except it only alters the named files.
#
#   tabify HEAD^
#     Remove tabs from the last git commit.
#
#   tabify -f
#     Remove tabs from pending git changes.
#     Note that it's safer to commit, then run "tabify HEAD^" (above).
#     You can then preview your changes and either commit or amend them.
#

require 'rubygems'
require 'open4'

def spawn(cmd, args, options)
  cmd  = cmd.to_a
  args = args.to_a

  options[:stdin]  ||= ''
  options[:stdout] ||= $stdout
  options[:stderr] ||= $stderr
  
  old_status = $?
  begin
    status = Open4.spawn(cmd + args, options)
  rescue Open4::SpawnError => e
    raise e unless e.status && e.status.exitstatus > 0
    exit(e.status.exitstatus)
  end
end

def error(message)
  $stderr.puts "tabify: #{message}"
end

def fail(message)
  error(message)
  exit(1)
end

def status(message)
  $stdout.puts "== #{message} =="
end

force_run = false
soft_tab  = '  '

until ARGV.empty?
  case ARGV.first
  when '-f'
    force_run = true
  when /^-(\d+)$/
    soft_tab = ' ' * $1.to_i
  else
    break
  end

  ARGV.shift
end

diff = ''
spawn ['git', 'diff'], ARGV, :stdout => diff
diff = diff.lines.to_a

fail "No changes found." if diff.empty?

unless force_run
  check_diff = ''
  spawn ['git', 'diff'], [], :stdout => check_diff
  fail "You have uncommitted changes.  Commit them or use \"tabify -f ...\"." unless check_diff.empty?
end

diff_no_tabs = diff.map do |line|
  if line =~ /^\+/
    line.gsub("\t", "  ")
  else
    line
  end
end

fail "No tabs to remove." if diff_no_tabs == diff

status "Reverting ..."
spawn 'patch', ['-p1', '-R'], :stdin => diff
status "Applying ..."
spawn 'patch', ['-p1'], :stdin => diff_no_tabs
status "Tabs converted!"
