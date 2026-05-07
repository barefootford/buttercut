#!/usr/bin/env ruby
# Verifies all ButterCut dependencies are installed

class DependencyChecker
  def run
    puts "ButterCut Dependency Check"
    puts "=" * 40
    puts

    results = []

    # Core dependencies (required)
    results << check("Xcode CLI Tools", "xcode-select -p", "xcode-select --install")
    results << check("Homebrew", "which brew", "See https://brew.sh")
    results << check_ruby_version
    results << check("Bundler", "which bundle", "gem install bundler")
    results << check_python_version
    results << check("FFmpeg", "which ffmpeg", "brew install ffmpeg")
    results << check_whisperx
    results << check_bundle_install

    # Optional: show mise status if installed (not required)
    check_mise_optional

    puts
    puts "=" * 40

    passed = results.count { |r| r[:status] == :ok }
    failed = results.select { |r| r[:status] == :missing }

    if failed.empty?
      puts "All #{passed} dependencies installed!"
      puts "ButterCut is ready to use."
      true
    else
      puts "#{passed}/#{results.size} dependencies installed"
      puts
      puts "Missing dependencies:"
      failed.each do |r|
        puts "  - #{r[:name]}: #{r[:install]}"
      end
      false
    end
  end

  private

  def check(name, cmd, install)
    result = system("#{cmd} > /dev/null 2>&1")
    status = result ? :ok : :missing
    icon = result ? "OK" : "MISSING"
    puts "#{icon.ljust(8)} #{name}"
    { name: name, status: status, install: install }
  end

  def check_ruby_version
    version_output = `ruby --version 2>/dev/null`.strip
    if version_output.match?(/ruby 3\.3/)
      puts "OK       Ruby (#{version_output.split[1]})"
      { name: "Ruby 3.3.x", status: :ok }
    elsif version_output.empty?
      puts "MISSING  Ruby"
      { name: "Ruby 3.3.x", status: :missing, install: "Install Ruby 3.3.6 (see .ruby-version)" }
    else
      puts "WRONG    Ruby (#{version_output.split[1]} - need 3.3.x)"
      { name: "Ruby 3.3.x", status: :missing, install: "Install Ruby 3.3.6 (see .ruby-version)" }
    end
  end

  def check_python_version
    version_output = `python3 --version 2>/dev/null`.strip
    if version_output.match?(/Python 3\.12/)
      puts "OK       Python (#{version_output.split[1]})"
      { name: "Python 3.12.x", status: :ok }
    elsif version_output.empty?
      puts "MISSING  Python"
      { name: "Python 3.12.x", status: :missing, install: "Install Python 3.12.8 (see .python-version)" }
    else
      puts "WRONG    Python (#{version_output.split[1]} - need 3.12.x)"
      { name: "Python 3.12.x", status: :missing, install: "Install Python 3.12.8 (see .python-version)" }
    end
  end

  def check_whisperx
    # Check various possible locations for whisperx
    locations = [
      "which whisperx",
      "test -x ~/.buttercut/whisperx",
      "test -x ~/.buttercut/venv/bin/whisperx"
    ]

    found = locations.any? { |cmd| system("#{cmd} > /dev/null 2>&1") }

    if found
      puts "OK       WhisperX"
      { name: "WhisperX", status: :ok }
    else
      puts "MISSING  WhisperX"
      { name: "WhisperX", status: :missing, install: "pip install whisperx (see setup instructions)" }
    end
  end

  def check_bundle_install
    gemfile_lock = File.join(Dir.pwd, "Gemfile.lock")

    if File.exist?(gemfile_lock)
      puts "OK       Bundle installed"
      { name: "Bundle installed", status: :ok }
    else
      puts "MISSING  Bundle installed"
      { name: "Bundle installed", status: :missing, install: "Run 'bundle install' in buttercut directory" }
    end
  end

  def check_mise_optional
    if system("which mise > /dev/null 2>&1")
      puts
      puts "(info)   Mise detected - using mise for version management"
    end
  end
end

success = DependencyChecker.new.run
exit(success ? 0 : 1)
