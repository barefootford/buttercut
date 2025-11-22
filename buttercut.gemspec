require_relative "lib/buttercut/version"

Gem::Specification.new do |spec|
  spec.name          = "buttercut"
  spec.version       = ButterCut::VERSION
  spec.authors       = ["Andrew Ford"]
  spec.email         = ["ford.andrewid@gmail.com"]

  spec.summary       = "Video Editor XML generator with Agent skills for analyzing video, creating rough cuts and sequences."
  spec.description   = "ButterCut generates video projects for Final Cut Pro and Adobe Premiere. It includes Claude Skills to perform metadata extraction through FFmpeg, audio extraction with WhisperX and visual analysis to create rough cuts and sequences."
  spec.homepage      = "https://github.com/andrewford/buttercut"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

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
  spec.add_dependency "rubyzip", "~> 2.3"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
end
