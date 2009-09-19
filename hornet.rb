#!/usr/bin/ruby

require 'thread'

should_shutdown = false

#listener = Thread.new {
  until should_shutdown
    begin
      f = File.open("/dev/tty.AG8004522-SerialPort-1")
      while true
        begin
          f.rewind
          puts f.read_nonblock(1024)
        rescue Errno::EAGAIN => e
          # do nothing, just wait
        end
      end
    rescue EOFError
      f.close
    rescue Errno::EBUSY
      # do nothing
    rescue Interrupt
      exit
    rescue Exception => e
      puts "Exception: #{e.class} - #{e}"
    end
  end
#}

