# config/initializers/allow_iframe.rb

Rails.application.config.action_dispatch.default_headers.delete('X-Frame-Options')
