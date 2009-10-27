#!/usr/bin/ruby

require 'thread'
require 'rubygems'
require 'pony'
require 'optparse'

def verbose(msg)
  # does nothing; code is replaced later
end

# logfile and rotation
logfile = File.open("/var/log/barcode.log", "a")

trap("SIGHUP") do
  logfile.close
  logfile = File.open("/var/log/barcode.log", "a")
end

options = {}
optparser = OptionParser.new do |opts|
  opts.banner = "Usage: barcode-daemon.rb -d device [recipients]"
  options[:wait] = 30
  
  # which device to run
  opts.on("-d", "--device DEVICE", "Use the barcode reader on DEVICE") do |d|
    options[:device] = d
  end
  
  # delay
  opts.on("-w", "--wait SECONDS", Integer, "Wait for scanner quiescence for SECONDS before sending (default: 30)") do |w|
    options[:wait] = w
  end
  
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
    def verbose(msg)
      puts msg
    end  
  end
  
end
optparser.parse!

# device is mandatory
if options[:device].nil?
  puts optparser.help
  exit
end

# at least one recipient
if ARGV.size == 0
  puts optparser.help
  exit
end

verbose "Starting up!"

should_shutdown = false
new_data = false
recv_buf = String.new
mutex = Mutex.new

def notify(message)
  verbose("Sending message...")
  Pony.mail(
    :to => ARGV.clone, 
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
  verbose("Message sent")
end

# This thread reads data from the scanner into recv_buf
listener = Thread.new {
  # wait for other initializtion first
  Thread.pass
  until should_shutdown
    begin
      f = File.open(options[:device])
      loop {
        begin
          # readpartial makes the thread sleep until something happens
          buf = f.readpartial(1024)
          mutex.synchronize {
            buf.split(/\n/).each do |line|
              verbose("Reader: #{line}")
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
      verbose("Exception: #{e.class} - #{e}")
      notify("Exception: #{e.class} - #{e}")
      exit
    end
  end
}

watchdog = Thread.new {
  loop {
    sleep(options[:wait])
    mutex.synchronize {
      if (should_shutdown || new_data == false) && recv_buf.length > 0
        verbose("Notifying")
        logfile.write recv_buf
        logfile.fsync
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

