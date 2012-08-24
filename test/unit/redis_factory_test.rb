require File.expand_path(File.dirname(__FILE__) + '/../test_helper.rb')

class RedisFactoryTest < ActiveSupport::TestCase
  
  setup do
    @oldconf = RedisFactory.class_variable_get("@@configuration")
    RedisFactory.class_variable_set("@@configuration", nil)
    @oldclients = RedisFactory.class_variable_get("@@clients")
    RedisFactory.class_variable_set("@@clients", {})
  end
  
  teardown do
    RedisFactory.class_variable_set("@@configuration", @oldconf)
    RedisFactory.class_variable_set("@@clients", @oldclients)
  end

  context "#configuration" do
    
    should "read in redis.yml" do
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
        foo:
            myredisdb:
              host: bar
      EOF
      )
      assert_equal({:myredisdb => {:db=>1, :host=>"localhost", :port=>6379, :thread_safe=>true}}, RedisFactory.configuration)
    end

    should "read in redis.yml for different env" do
      Rubber.expects(:env).returns("foo")
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
        foo:
            myredisdb:
              host: bar
      EOF
      )
      assert_equal({:myredisdb => {:host=>"bar"}}, RedisFactory.configuration)
    end

  end

  context "#connect" do
  
    should "return client for symbol" do
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
            cache:
              db: 2
              host: localhost
              port: 6379
              thread_safe: true
      EOF
      )
      assert_equal 1, RedisFactory.connect(:myredisdb).client.db
      assert_equal 2, RedisFactory.connect(:cache).client.db
    end
    
    should "reuse client for same symbol" do
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
      EOF
      )
      assert_equal RedisFactory.connect(:myredisdb), RedisFactory.connect(:myredisdb) 
    end
    
    should "return standard redis client if no zkservers" do
      client = mock()
      ::Redis.expects(:new).returns(client)
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
      EOF
      )
      assert_equal client, RedisFactory.connect(:myredisdb)
    end

    should "return failover redis client if zkservers present" do
      client = mock()
      ::RedisFailover::Client.expects(:new).returns(client)
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
              zkservers: foo
      EOF
      )
      assert_equal client, RedisFactory.connect(:myredisdb)
    end

  end
  
  context "#disconnect" do

    setup do
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
            cache:
              db: 2
              host: localhost
              port: 6379
              thread_safe: true
      EOF
      )
    end
  
    should "disconnect specific client" do
      myredisdb_client = RedisFactory.connect(:myredisdb)
      cache_client = RedisFactory.connect(:cache)
      
      myredisdb_client.expects(:quit)
      cache_client.expects(:quit).never
      RedisFactory.disconnect(:myredisdb)
    end
    
    should "disconnect all clients" do
      myredisdb_client = RedisFactory.connect(:myredisdb)
      cache_client = RedisFactory.connect(:cache)
      
      myredisdb_client.expects(:quit)
      cache_client.expects(:quit)
      RedisFactory.disconnect
    end
    
  end
  
  context "#reconnect" do

    setup do
      IO.expects(:read).with("#{Rubber.root}/config/redis.yml").returns(<<-EOF
        test:
            myredisdb:
              db: 1
              host: localhost
              port: 6379
              thread_safe: true
            cache:
              db: 2
              host: localhost
              port: 6379
              thread_safe: true
      EOF
      )
    end
  
    should "reconnect specific client" do
      myredisdb_client = RedisFactory.connect(:myredisdb)
      cache_client = RedisFactory.connect(:cache)
      
      myredisdb_client.expects(:client).returns(mock('redis', :reconnect => nil))
      cache_client.expects(:client).never
      RedisFactory.reconnect(:myredisdb)
    end
    
    should "reconnect all clients" do
      myredisdb_client = RedisFactory.connect(:myredisdb)
      cache_client = RedisFactory.connect(:cache)
      
      myredisdb_client.expects(:client).returns(mock('redis', :reconnect => nil))
      cache_client.expects(:client).returns(mock('redis', :reconnect => nil))
      RedisFactory.reconnect
    end
    
  end
  
end
