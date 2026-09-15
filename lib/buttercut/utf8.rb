# frozen_string_literal: true

# Everything ButterCut reads and writes — library.yaml, cut YAML, transcript
# JSON, the filenames macOS and Windows hand over — is UTF-8. Ruby, though,
# tags ARGV and untyped file I/O with the shell's locale, and a shell that
# never sourced its profile (no LANG or LC_*) reports US-ASCII. A clip name
# with an em dash then arrives as an invalid US-ASCII string: Psych stores it
# as `!binary`, loads it back as ASCII-8BIT, and the same bytes no longer
# equal the UTF-8 name in a cut, so the export silently drops the clip
# (ButterCut report 18). JSON refuses to serialize it at all (report 20).
#
# Every entry point calls `setup!` (through version.rb) so the process is
# UTF-8 regardless of the shell that started it, and the YAML loaders retag
# paths that an older run already stored as binary.
class ButterCut
  module UTF8
    def self.setup!
      Encoding.default_external = Encoding::UTF_8 unless Encoding.default_external == Encoding::UTF_8
      ARGV.map! { |arg| retag(arg) }
    end

    # The UTF-8 reading of a string Ruby tagged with some other encoding,
    # left alone when the bytes are not valid UTF-8 (nothing better exists).
    def self.retag(str)
      return str unless str.is_a?(String) && str.encoding != Encoding::UTF_8

      utf8 = str.dup.force_encoding(Encoding::UTF_8)
      utf8.valid_encoding? ? utf8 : str
    end

    # Fix up a freshly loaded library.yaml hash in place: media paths stored
    # as `!binary` come back as ASCII-8BIT and must compare equal to UTF-8.
    def self.heal_media_paths!(library)
      Array(library['media']).each { |media| media['path'] = retag(media['path']) }
      library
    end
  end
end
