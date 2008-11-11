module Deployable
  class RosterMember
    attr_accessor :node, :jid, :features
    
    def initialize(args)
      @node = args[:node]
      @jid  = args[:jid]
      @features = args[:features] || []
    end
  end
end