require 'eventmachine'

module Deployable
  class Sleepworker
    include EM::Deferrable
    
    def test args
      sleep(10)
      set_deferred_status :succeeded, "Sleep Success"
    end
  end
end