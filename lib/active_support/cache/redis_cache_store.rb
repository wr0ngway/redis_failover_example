require "backupify/logger_support"

module ActiveSupport
  module Cache

    class RedisCacheStore < ActiveSupport::Cache::Store
      
      include Backupify::LoggerSupport
      
      # Creates a new RedisStore object, with the given redis server
      # address. Each address is a valid redis url string. For example:
      #
      #   ActiveSupport::Cache::RedisStore.new("redis://127.0.0.1:6379/0")
      #
      # Instead of addresses one can pass in a redis-like object. For example:
      #
      #   require 'redis' # gem install redis; uses C bindings to libredis
      #   ActiveSupport::Cache::RedisStore.new(Redis.connect("localhost"))
      def initialize(*connections)
        options = connections.extract_options!
        super(options)
        
        raise ArgumentError, "Only a single connection must be provided" if connections.size > 1
        connection = connections.first || options
        
        if connection.respond_to?(:get)
          @data = connection
        elsif connection.is_a?(Symbol)
          require 'redis_factory'
          @data = RedisFactory.connect(connection)            
        else
          redis_options = {}
          if connection.is_a?(String)
            redis_options[:url] = connection
          elsif connection.is_a?(Hash)
            redis_options = connection
            ActiveSupport::Cache::UNIVERSAL_OPTIONS.each{|name| redis_options.delete(name)}
          else
            raise ArgumentError, "Need a url or hash for a redis connection"
          end
          
          @data = ::Redis.connect(redis_options)
        end
  
        extend ActiveSupport::Cache::Strategy::LocalCache
      end
  
      # Reads multiple values from the cache using a single call to the
      # servers for all keys. Options can be passed in the last argument.
      def read_multi(*names)
        options = names.extract_options!
        options = merged_options(options)
        keys_to_names = Hash[names.map{|name| [namespaced_key(name, options), name]}]
        raw_values = @data.mget(keys_to_names.keys)
        values = {}
        raw_values.each do |key, value|
          entry = deserialize_entry(value)
          values[keys_to_names[key]] = entry.value unless entry.expired?
        end
        values
      end
  
      # Delete objects for matched keys.
      #
      # Example:
      #   cache.del_matched "rab*"
      def delete_matched(matcher, options = nil) # :nodoc:
        options = merged_options(options)
        response = instrument(:delete_matched, matcher.inspect) do
          matcher = key_matcher(matcher, options)
          @data.keys(matcher).each { |key| @data.del key }
        end
      rescue => e
        logger.error("Error calling delete_matched on redis: #{e}") if logger
        nil
      end

      # Increment a cached value. This method uses the redis incrby atomic
      # operator
      def increment(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        response = instrument(:increment, name, :amount => amount) do
          @data.incrby(namespaced_key(name, options), amount)
        end
      rescue => e
        logger.error("Error incrementing cache entry in redis: #{e}") if logger
        nil
      end
  
      # Decrement a cached value. This method uses the redis decrby atomic
      # operator
      def decrement(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        response = instrument(:decrement, name, :amount => amount) do
          @data.decrby(namespaced_key(name, options), amount)
        end
      rescue => e
        logger.error("Error decrementing cache entry in redis: #{e}") if logger
        nil
      end
  
      # Clear the entire cache on all redis servers. This method should
      # be used with care when shared cache is being used.
      def clear(options = nil)
        @data.flushdb
      end
  
      # Get the statistics from the redis servers.
      def stats
        @data.info
      end
  
      protected
      
      # Read an entry from the cache.
      def read_entry(key, options) # :nodoc:
        deserialize_entry(@data.get(key))
      rescue => e
        logger.error("Error reading cache entry from redis: #{e}") if logger
        nil
      end
  
      # Write an entry to the cache.
      def write_entry(key, entry, options) # :nodoc:
        value = serialize_entry(entry)
        if (options && options[:expires_in])
          expires_in = options[:expires_in].to_i
          response = @data.setex(key, expires_in, value)
        else
          response = @data.set(key, value)
        end
      rescue => e
        logger.error("Error writing cache entry to redis: #{e}") if logger
        false
      end
  
      # Delete an entry from the cache.
      def delete_entry(key, options) # :nodoc:
        response = @data.del(key)
      rescue => e
        logger.error("Error deleting cache entry from redis: #{e}") if logger
        false
      end
  
      private
  
      def deserialize_entry(raw_value)
        if raw_value
          entry = Marshal.load(raw_value) rescue raw_value
          entry.is_a?(ActiveSupport::Cache::Entry) ? entry : ActiveSupport::Cache::Entry.new(entry)
        else
          nil
        end
      end
  
      def serialize_entry(entry)
        if entry
          Marshal.dump(entry)
        else
          nil
        end
      end
  
    end

  end
end
