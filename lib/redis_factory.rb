# A factory class for creating redis connections, and reconnecting them after a fork
#
# It uses RedisFailover as the client if config/redis.yml contains a
# zkservers setting for the named connection, otherwise vanilla redis client
class RedisFactory
  extend MonitorMixin
  
  @@configuration = nil
  @@clients = {}
  
  def self.logger; Rails.logger; end
  
  # Creates a redis client for the given named configuration
  #
  # @param [String] name The name of the redis configuration (config/redis.yml) )to use
  # @return [RedisClient] A redis client object (may be a failover capable proxy)
  def self.connect(name)
    conf = configuration[name]
    raise "No redis configuration for #{Rubber.env} environment in redis.yml for #{name}" unless conf
    synchronize do
      if conf[:zkservers]
        conf[:logger] = logger
        @@clients[name] ||= ::RedisFailover::Client.new(conf)
      else
        @@clients[name] ||= ::Redis.new(conf)
      end
    end
    @@clients[name]
  end

  def self.disconnect(key=nil)
    logger.debug "RedisFactory.disconnect start"
    synchronize do
      @@clients.clone.each do |name, client|
        next if key && name != key

        client = @@clients.delete(name)
        if client
          begin
            if client.instance_of?(::RedisFailover::Client)
              logger.debug "Disconnecting RedisFailover client: #{client}"
              client.shutdown
            elsif client.instance_of?(::Redis)
              logger.debug "Disconnecting Redis client: #{client}"
              client.quit
            else
              logger.warn("Couldn't reconnect unknown redis client type: #{client.class}")
            end
          rescue => e
            logger.warn("Exception while disconnecting: #{e}")
          end
        end
      end
    end
    logger.debug "RedisFactory.disconnect complete"    
  end

  def self.reconnect(key=nil)
    logger.debug "RedisFactory.reconnect start"
    synchronize do
      @@clients.each do |name, client|
        next if key && name != key
        
        if client.instance_of?(::RedisFailover::Client)
          logger.debug "Reconnecting RedisFailover client: #{client}"
          client.reconnect
        elsif client.instance_of?(::Redis)
          logger.debug "Reconnecting Redis client: #{client}"
          client.client.reconnect
        else
          logger.warn("Couldn't reconnect unknown redis client type: #{client.class}")
        end
      end
    end
    logger.debug "RedisFactory.reconnect complete"    
  end
  
  def self.configuration
    synchronize do
      @@configuration ||= begin
        require 'erb'
        config = YAML::load(ERB.new(IO.read("#{Rubber.root}/config/redis.yml")).result)
        self.symbolize(config[Rubber.env])
      end
    end
  end
  
  private
  
  def self.symbolize(hash)
    hash.inject({}) do |options, (key, value)|
      value = self.symbolize(value) if value.kind_of?(Hash)
      options[key.to_sym || key] = value
      options
    end
  end
  
end
