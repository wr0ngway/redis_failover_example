require File.expand_path('../boot', __FILE__)
root =  File.expand_path('../..', __FILE__)

require 'rails/all'


if defined?(Bundler)
  # If you precompile assets before deploying to production, use this line
  Bundler.require(*Rails.groups(:assets => %w(development test)))
  # If you want your assets lazily compiled in production, use this line
  # Bundler.require(:default, :assets, Rails.env)
end

module Appleton
  class Application < Rails::Application

    config.cache_store = :redis_cache_store, :cache
    
  end
end
