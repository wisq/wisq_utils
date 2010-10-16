module Uniterm
  module Common
    def uni_popen(*command)
      IO.popen('-', 'r') do |fh|
        if fh.nil?
          uni_exec(*command)
        else
          if block_given?
            yield fh
          else
            return fh.read
          end
        end
      end
    end

    def uni_exec(cmd, *args)
      args = args.map(&:to_s)
      ENV.delete('RUBYOPT')
      exec(cmd.to_s, *args)
      raise "exec(#{cmd}) failed"
    end
  end  
end
