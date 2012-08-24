if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      # We're in smart spawning mode.
    
      # Reset redis failover clients
      RedisFactory.reconnect
    else
      # We're in conservative spawning mode. We don't need to do anything.
    end
  end
end
