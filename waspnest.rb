#!/usr/bin/ruby

require 'thread'
require 'rubygems'
require 'pony'

should_shutdown = false
new_data = false
recv_buf = String.new
mutex = Mutex.new

def notify(message)
  Pony.mail(
    :to => "jamesez@umich.edu", 
    :from => "jamesez@umich.edu",
    :subject => "[BARCODE] Barcode Reader",
    :body => message,
    :via => :smtp, 
    :smtp => { 
      :host => "mx1.umich.edu",
      :port => '25', 
      :domain => 'plausible.lsi.umich.edu' 
    }
  )
end

# This thread reads data from the scanner into recv_buf
listener = Thread.new {
  # wait for other initializtion first
  Thread.pass
  until should_shutdown
    begin
      f = File.open("/dev/tty.AG8004522-SerialPort")
      loop {
        begin
          # readpartial makes the thread sleep until something happens
          buf = f.readpartial(1024)
          mutex.synchronize {
            buf.split(/\n/).each do |line|
              recv_buf.concat Time.now.strftime("%a %d %T") + " " + line + "\n"
            end
            new_data = true
          }
        rescue Errno::EAGAIN => e
          # do nothing, just wait
        end
      }
    rescue EOFError
      f.close
    rescue Errno::EBUSY
      # do nothing, just reopen
    rescue Interrupt
      should_shutdown = true
      Thread.exit
    rescue Exception => e
      notify("Exception: #{e.class} - #{e}")
      exit
    end
  end
}

watchdog = Thread.new {
  loop {
    sleep(10)
    mutex.synchronize {
      if (should_shutdown || new_data == false) && recv_buf.length > 0
        notify(recv_buf.clone)
        recv_buf = String.new
      end

      if new_data
        new_data = false
      end
      
      if should_shutdown && recv_buf.length == 0
        Thread.exit
      end
    }
  }
}

trap("INT") do
  if should_shutdown
    puts "Caught fatal INT"
    exit
  else
    puts "Got INT, shutting down..."

    should_shutdown = true
    watchdog.wakeup
    
  end
  # end listener immediately
  listener.exit
end

# wait for threads to exit
listener.join
watchdog.join

