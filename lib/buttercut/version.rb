class ButterCut
  VERSION = "0.9.0"
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
