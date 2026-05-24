require_relative "lib/buttercut/version"

Gem::Specification.new do |spec|
  spec.name          = "buttercut"
  spec.version       = ButterCut::VERSION
  spec.authors       = ["Andrew Ford"]
  spec.email         = ["ford.andrewid@gmail.com"]

  spec.summary       = "[DEPRECATED] ButterCut is no longer distributed as a gem."
  spec.description   = "ButterCut's XML generator has been merged into the main agent code. See https://github.com/barefootford/buttercut. The 0.7.x gem continues to function but will not be updated."
  spec.homepage      = "https://github.com/barefootford/buttercut"
  spec.license       = "Nonstandard"
  spec.required_ruby_version = ">= 2.7.0"

  spec.post_install_message = <<~MSG
    buttercut is no longer published as a gem.
    The XML generator now ships with the agent code at:
      https://github.com/barefootford/buttercut
    The 0.7.x line continues to function but will not be updated.
  MSG

  spec.files = Dir[
    "lib/**/*",
    ".claude/**/*",
    "templates/**/*",
    "dtd/**/*",
    "bin/**/*",
    "README.md",
    "CLAUDE.md",
    "LICENSE",
    "buttercut.yaml"
  ]

  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "nokogiri", "~> 1.13"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
end
