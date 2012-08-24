Resque.redis = RedisFactory.connect(:resque)

# reopen redis connection in forked child.
#
redis_factory_chained_after_fork_hook = Resque.after_fork
Resque.after_fork do |job|
  # Reset redis failover clients in worker child so that they
  # don't conflict (deadlock) with the ones in worker parent
  RedisFactory.reconnect

  redis_factory_chained_after_fork_hook.call(job) if redis_factory_chained_after_fork_hook
end

