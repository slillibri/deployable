require 'eventmachine'
require 'net/http'
require 'log4r'

module Deployable  
  class Worker
    include EM::Deferrable
    include Log4r
    
    def initialize (*args)
      @logger = Log4r::Logger.new "workerlog"
      @logger.outputters = Log4r::FileOutputter.new("workerlog", :filename => 'worker.log', :trunc => false)
      @logger.level = DEBUG
    end
    
    def method_missing
      set_deferred_status :failed, {:message => 'No such task'}
    end
    
    def lift *args
      30.times do |i|
        @logger.debug "Lifted #{i}"
        sleep 0.1
      end
      set_deferred_status :succeeded, {:message => 'Lift successful'}
    end
  
    def fetch *args
      url = args.shift
  
      begin
        @logger.debug "Starting to test #{url[0]}"
        res = Net::HTTP.start(url[0],80) {|http|
          http.read_timeout=30
          http.get("/")
        }
        if res.code.to_i != 200
          set_deferred_status :failed, {:code => res.code, :message => res.message}
        else
          set_deferred_status :succeeded, {:code => res.code, :message => res.message}
        end
      rescue
        $@.each do |err|
          @logger.warn "\t#{err}" if @logger.level <= WARN
        end
        set_deferred_status :failed, {:message => "Super fail! #{$!}"}
      end
    end
    
    def test *args
      begin
        command = 'cat TEST'
        result = `#{command}`
        result.gsub!(/\W*/, '')
        case result
        when "UP" :
          set_deferred_status :succeeded, {:message => 'OK'}
        when "DOWN" :
          set_deferred_status :failed, {:message => 'CRITICAL'}
        else
          set_deferred_status :failed, {:message => 'UNKNOWN'}
        end      
      rescue
        set_deferred_status :failed, {:message => 'UNKNOWN'}
      end    
    end
  end
end