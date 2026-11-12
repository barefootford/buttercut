require_relative 'utf8'

# Every entry point loads this file, so this is where the process turns
# UTF-8 no matter what locale the shell that launched it had — see utf8.rb.
ButterCut::UTF8.setup!

class ButterCut
  # ButterCut has no version numbers to bump. Changes ship as they merge and
  # CHANGELOG.md groups them by month, so the newest heading there
  # ("## November 2026") names what an install is running: RELEASE is that
  # month, VERSION its sortable form ("2026.11"). Add a changelog line under a
  # new month and both follow.
  CHANGELOG = File.expand_path('../../CHANGELOG.md', __dir__)
  MONTHS = %w[January February March April May June July August September October November December].freeze
  RELEASE_HEADING = /^## (#{MONTHS.join('|')}) (?:\d{1,2}, )?(\d{4})\s*$/

  # [month name, year] from the newest changelog heading; nil when there is no
  # changelog to read.
  def self.newest_release(changelog = CHANGELOG)
    File.foreach(changelog) do |line|
      match = line.match(RELEASE_HEADING)
      return [match[1], match[2].to_i] if match
    end
    nil
  rescue SystemCallError
    nil
  end

  release_month, release_year = newest_release
  RELEASE = release_month ? "#{release_month} #{release_year}" : 'unknown'
  VERSION = release_month ? format('%d.%02d', release_year, MONTHS.index(release_month) + 1) : 'unknown'
  EDITION = :core # :core for open-source ButterCut, :pro for ButterCut Pro

  def self.pro?
    EDITION == :pro
  end

  def self.core?
    EDITION == :core
  end

  # Resolve an engine file to this edition's variant, for `require_relative` in
  # the shims (editor_base.rb, export.rb, fcpx.rb, fcp7.rb). Pro loads the
  # multi-track "<base>_pro" file when it's present; core — and Pro before the
  # multi-track files are added — loads the single-track "<base>_core".
  def self.engine_variant(base)
    pro_variant = "#{base}_pro"
    return pro_variant if pro? && File.exist?(File.join(__dir__, "#{pro_variant}.rb"))

    "#{base}_core"
  end

  # Load this edition's optional extension for a shared file, if it ships one.
  # Unlike engine_variant (which swaps a whole file), this layers Pro behavior
  # onto a file both editions share — see library.rb.
  def self.load_extension(base)
    path = File.join(__dir__, "#{base}_pro.rb")
    require path if pro? && File.exist?(path)
  end
end
