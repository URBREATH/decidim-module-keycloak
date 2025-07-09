# config/initializers/allow_iframe.rb

Rails.application.config.action_dispatch.default_headers.delete('X-Frame-Options')
# oppure per permettere solo da localhost:8080:
Rails.application.config.action_dispatch.default_headers['X-Frame-Options'] = "ALLOW-FROM http://localhost:8080"
