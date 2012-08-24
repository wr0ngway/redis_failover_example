require File.expand_path(File.dirname(__FILE__) + '/../../../test_helper.rb')
require 'rbconfig'

class RedisCacheStoreTest < ActiveSupport::TestCase

  def get_redis_server_pid
    pid = `ps -e -o pid,command | grep [r]edis-server | grep -v sh`.split(" ")[0]
  end
  
  def kill_redis_server(sig="KILL")
    pid = get_redis_server_pid
    pid = pid.to_i
    raise "Invalid pid" if pid == 0
    if RbConfig::CONFIG['host_os'] =~ /linux/i
      system("sudo /bin/kill -#{sig} #{pid}") || fail("Couldn't kill -#{sig} redis")
    else
      Process.kill(sig, pid)
    end
  end
  
  def start_redis_server
    if RbConfig::CONFIG['host_os'] =~ /linux/i
      system("sudo /usr/sbin/service redis-server start") || fail("Couldn't start redis")
    else
      ENV['PATH'] += ":/usr/local/bin" unless ENV['PATH'] =~ /\/usr\/local\/bin/
      spawn "nohup redis-server", :chdir => "/tmp/", [:out, :err] => ["redis.log", "w"]
    end
  end
  
  context "integrated into rails cache" do
    
    should "be using redis cache store" do
      assert_equal ActiveSupport::Cache::RedisCacheStore, Rails.cache.class
      assert Rails.cache.kind_of?(ActiveSupport::Cache::Store)
    end

    should "perform read/write correctly" do
      assert_nil Rails.cache.read("foo")
      Rails.cache.write("foo", "bar")
      assert_equal "bar", Rails.cache.read("foo")
    end
  
    should "handle basic types in read/write correctly" do
      assert_nil Rails.cache.read("foo")
      Rails.cache.write("foo", "bar")
      assert_equal "bar", Rails.cache.read("foo")

      Rails.cache.write("foo", 1)
      assert_equal 1, Rails.cache.read("foo")
      
      Rails.cache.write("foo", ['x'])
      assert_equal ['x'], Rails.cache.read("foo")

      Rails.cache.write("foo", {'x' => 2})
      assert_equal({'x' => 2}, Rails.cache.read("foo"))
    end
  
    should "perform increment correctly" do
      assert_nil Rails.cache.read("foo")
      assert_equal 1, Rails.cache.increment("foo")
      assert_equal "1", Rails.cache.read("foo")
      assert_equal 4, Rails.cache.increment("foo", 3)
      assert_equal "4", Rails.cache.read("foo")
    end
  
    should "perform decrement correctly" do
      assert_nil Rails.cache.read("foo")
      assert_equal -1, Rails.cache.decrement("foo")
      assert_equal "-1", Rails.cache.read("foo")
      assert_equal -4, Rails.cache.decrement("foo", 3)
      assert_equal "-4", Rails.cache.read("foo")
    end
  
    should "fail to increment/decrement on value set through write" do
      # implement :raw support in ActiveSupport::Cache::RedisCacheStore if this is desired
      assert_nil Rails.cache.read("foo")
      Rails.cache.write("foo", 5)
      assert_nil Rails.cache.increment("foo")
      assert_nil Rails.cache.decrement("foo")
    end
  
    should "perform fetch correctly" do
      assert_nil Rails.cache.fetch("foo")
      assert_equal "bar", Rails.cache.fetch("foo") { "bar" }
      assert_equal "bar", Rails.cache.read("foo")
      assert_equal "bar", Rails.cache.fetch("foo")
    end

  end
  
  context "behave in a failsafe way" do
  
    context "when server is down" do
  
      setup do
        conf = RedisFactory.configuration[:cache]
        @cache = ActiveSupport::Cache::RedisCacheStore.new(conf.merge(:port => 9999, :timeout => 0.1))
      end
      
      should "still perform fetch correctly" do
        assert_nil @cache.fetch("foo")
        assert "bar", @cache.fetch("foo") { "bar" }
      end
  
      should "return nil on read" do
        assert_nil @cache.read("foo")
      end
  
      should "return false on write" do
        assert ! @cache.write("foo", "bar")
      end
  
      should "return false on delete" do
        assert ! @cache.delete("foo")
      end
  
    end

    context "when server is up" do
      
      setup do
        conf = RedisFactory.configuration[:cache]
        @cache = ActiveSupport::Cache::RedisCacheStore.new(conf.merge(:timeout => 0.1))
      end
  
      
      should "handle restarted server" do
        assert_equal nil, Rails.cache.read("foo")
        Rails.cache.write("foo", "bar")
        assert_equal "bar", Rails.cache.read("foo")
        
        Rails.cache.instance_eval{@data}.save
        kill_redis_server
        while get_redis_server_pid != nil; Rails.logger.info("Waiting for redis to stop"); sleep 0.1; end
      
        assert_equal nil, Rails.cache.read("foo")
        assert_equal false, Rails.cache.write("foo", "bar")
        assert_equal nil, Rails.cache.read("foo")
      
        start_redis_server
        while get_redis_server_pid.nil?; Rails.logger.info("Waiting for redis to start"); sleep 0.1; end        
      
        assert_equal "bar", Rails.cache.read("foo")
        Rails.cache.write("foo", "baz")
        assert_equal "baz", Rails.cache.read("foo")
      end
      
      should "handle stopped server" do
        begin
          kill_redis_server("STOP")
          sleep 0.1
          
          assert_equal nil, Rails.cache.read("foo")
          Rails.cache.write("foo", "bar")
          assert_equal nil, Rails.cache.read("foo")
        
          kill_redis_server("CONT")
          sleep 0.1
          
          assert_equal nil, Rails.cache.read("foo")
          Rails.cache.write("foo", "bar")
          assert_equal "bar", Rails.cache.read("foo")
        ensure
          kill_redis_server("CONT")
          sleep 0.1
        end
      end
  
    end
    
  end
  
end
