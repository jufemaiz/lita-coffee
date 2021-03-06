require 'lita'

Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

require_relative "lita/handlers/coffee"
require 'lita-coffee/version'

Lita::Handlers::Coffee.template_root File.expand_path(
  File.join("..", "..", "templates"),
 __FILE__
)
