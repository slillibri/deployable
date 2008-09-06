require 'eventmachine'
require 'log4r'

module Deployable  
  class Lifter 
    include EM::Deferrable
    include Log4r
    
    def initialize (*args)
    end
    
    def method_missing method
      set_deferred_status :failed, {:message => 'No such task'}
    end

    def lift *args
      30.times do |i|
        sleep 0.1
      end
      set_deferred_status :succeeded, {:message => 'Lift successful'}
    end
  end
end