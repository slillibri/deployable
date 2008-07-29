require 'eventmachine'
require 'log4r'

module Deployable  
  class Lifter 
    include EM::Deferrable
    include Log4r
    
    def initialize (*args)
      @logger = Log4r::Logger.new "workerlog"
      @logger.outputters = Log4r::FileOutputter.new("workerlog", :filename => 'worker.log', :trunc => false)
      @logger.trace = true
      @logger.level = DEBUG
    end
    
    def method_missing method
      @logger.debug "No method #{method}"
      set_deferred_status :failed, {:message => 'No such task'}
    end

    def lift *args
      30.times do |i|
        @logger.debug "Lifted #{i}"
        sleep 0.1
      end
      set_deferred_status :succeeded, {:message => 'Lift successful'}
    end
  end
end