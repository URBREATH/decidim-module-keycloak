# frozen_string_literal: true

base_path = File.expand_path("..", __dir__)


Decidim::Shakapacker.register_path("#{base_path}/app/packs", prepend: true)

Decidim::Shakapacker.register_entrypoints(
  decidim_keycloak: "#{base_path}/app/packs/entrypoints/decidim_keycloak.js"
)

