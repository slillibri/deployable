require 'eventmachine'
require 'net/http'
require 'log4r'

module Deployable  
  class Worker
    include EM::Deferrable
    include Log4r
    
    def initialize (*args)
    end
    
    def method_missing method
      set_deferred_status :failed, {:message => 'No such task'}
    end

    def list_tasks
      methods = [Object.public_methods].flatten
      self.public_methods.reject {|each| methods.include?(each)}
    end
    
    def lift *args
      30.times do |i|
        sleep 0.1
      end
      set_deferred_status :succeeded, {:message => 'Lift successful'}
    end

    def fetch *args
      url = args.shift

      begin
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