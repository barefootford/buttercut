require 'yaml'
require 'date'

class ButterCut
  # B-roll manifest emitted by the director and consumed by the render skill
  # and roughcut integration. One entry per generated graphic. See
  # templates/broll_template.yaml for the canonical schema example and the
  # Hyperframes epic (#63) for context.
  class BrollManifest
    SCHEMA_VERSION = 1

    PLACEMENTS = %w[overlay cutaway pip].freeze

    def self.from_hash(hash)
      raise ArgumentError, "manifest hash required" unless hash.is_a?(Hash)

      new(
        version: hash["version"],
        library: hash["library"],
        roughcut: hash["roughcut"],
        entries: hash["entries"]
      )
    end

    def self.load(path)
      from_hash(YAML.load_file(path, permitted_classes: [Date, Time, Symbol]))
    end

    def initialize(version:, library:, roughcut:, entries:)
      @version = version
      @library = library
      @roughcut = roughcut.nil? ? "" : roughcut
      @entries = entries

      validate!
    end

    attr_reader :version, :library, :roughcut, :entries

    def to_h
      {
        "version" => @version,
        "library" => @library,
        "roughcut" => @roughcut,
        "entries" => @entries
      }
    end

    def save(path)
      File.write(path, to_h.to_yaml)
    end

    private

    def validate!
      validate_version!
      validate_string!(@library, "library")
      raise ArgumentError, "roughcut must be a string" unless @roughcut.is_a?(String)
      validate_entries!
    end

    def validate_version!
      raise ArgumentError, "version must be #{SCHEMA_VERSION}, got #{@version.inspect}" unless @version == SCHEMA_VERSION
    end

    def validate_string!(value, field)
      raise ArgumentError, "#{field} required" if !value.is_a?(String) || value.empty?
    end

    def validate_non_negative_number!(value, field)
      raise ArgumentError, "#{field} must be a non-negative number, got #{value.inspect}" unless value.is_a?(Numeric) && value >= 0
    end

    def validate_entries!
      raise ArgumentError, "entries must be an array" unless @entries.is_a?(Array)

      @entries.each { |entry| validate_entry!(entry) }

      ids = @entries.map { |e| e["id"] }
      duplicates = ids.tally.select { |_, count| count > 1 }.keys
      unless duplicates.empty?
        raise ArgumentError, "entry ids must be unique, duplicates: #{duplicates.inspect}"
      end
    end

    def validate_entry!(entry)
      raise ArgumentError, "entry must be a hash" unless entry.is_a?(Hash)

      validate_string!(entry["id"], "entry id")
      id = entry["id"]
      validate_string!(entry["source_video"], "entry #{id} source_video")
      validate_string!(entry["template"], "entry #{id} template")

      validate_non_negative_number!(entry["start"], "entry #{id} start")
      validate_non_negative_number!(entry["end"], "entry #{id} end")
      unless entry["end"] > entry["start"]
        raise ArgumentError, "entry #{id} end (#{entry["end"]}) must be greater than start (#{entry["start"]})"
      end

      unless PLACEMENTS.include?(entry["placement"])
        raise ArgumentError, "entry #{id} placement #{entry["placement"].inspect} not in #{PLACEMENTS.inspect}"
      end

      if entry.key?("score") && !entry["score"].nil?
        score = entry["score"]
        unless score.is_a?(Numeric) && score >= 0 && score <= 1
          raise ArgumentError, "entry #{id} score must be in 0..1, got #{score.inspect}"
        end
      end

      content = entry["content"]
      raise ArgumentError, "entry #{id} content must be a hash" unless content.is_a?(Hash)
      raise ArgumentError, "entry #{id} content must not be empty" if content.empty?

      if entry.key?("rendered") && !entry["rendered"].nil?
        validate_string!(entry["rendered"], "entry #{id} rendered")
      end

      if entry.key?("notes") && !entry["notes"].nil? && !entry["notes"].is_a?(String)
        raise ArgumentError, "entry #{id} notes must be a string"
      end
    end
  end
end
