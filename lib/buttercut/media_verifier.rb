# frozen_string_literal: true

# Verifies that a set of media paths still resolve where the library expects,
# and — for `/Volumes` drives that have drifted — suggests a relink.
#
# Two macOS failure modes motivate this:
#   * A drive renamed at mount time: a leftover `/Volumes/Andrew SSD` folder makes
#     macOS mount the real drive as `/Volumes/Andrew SSD 1`, so stored paths miss.
#   * The nastier variant: files copied INTO that leftover `/Volumes/Andrew SSD`
#     folder — which lives on the internal boot disk — while the drive was
#     unplugged. The stale path resolves (`File.exist?` is true) but points at
#     the wrong copy. A bare existence check passes; this is the "phantom" case.
#
# Read-only: inspects the filesystem, never writes. Both the export pre-flight
# and `Library#verify_media` build one over a list of paths.
# `root_dev` and `volumes_root` are injectable so the whole thing is testable in
# a tmpdir without fabricating device numbers.
class MediaVerifier
  def initialize(paths, root_dev: nil, volumes_root: '/Volumes')
    @paths = Array(paths)
    @volumes_root = volumes_root.to_s.chomp('/')
    # The boot-disk baseline is the device volumes_root itself lives on — not
    # `/`, which on APFS can be a sealed system snapshot with a different dev
    # than the Data volume `/Volumes` is firmlinked into. A folder created
    # inside /Volumes shares its parent's device; a real mount has its own.
    @root_dev = root_dev || device_of(@volumes_root)
  end

  # [{ 'filename', 'path', 'status' }] in input order; status ∈ ok|missing|phantom.
  def media
    @media ||= @paths.map do |path|
      { 'filename' => File.basename(path), 'path' => path, 'status' => status_of(path) }
    end
  end

  def ok?      = media.all? { |m| m['status'] == 'ok' }
  def problems = media.reject { |m| m['status'] == 'ok' }

  # The full read-only report `verify_media` prints as JSON.
  def report
    {
      'media' => media,
      'ok_count' => count('ok'),
      'missing_count' => count('missing'),
      'phantom_count' => count('phantom'),
      'phantom_volumes' => phantom_volumes,
      'suggested_relinks' => suggested_relinks
    }
  end

  # Distinct volume-root prefixes (`/Volumes/<X>`) that are leftover squatter
  # folders on the boot disk.
  def phantom_volumes
    media.filter_map { |m| volume_prefix(m['path']) if m['status'] == 'phantom' }.uniq
  end

  # Prefix remaps that would fix the MISSING files (phantoms excluded — divergent
  # copies need a human). One entry per old prefix, only when all its misses agree.
  def suggested_relinks
    media.select { |m| m['status'] == 'missing' }
         .group_by { |m| volume_prefix(m['path']) }
         .filter_map do |old_prefix, entries|
           next unless old_prefix

           targets = entries.map { |m| remap_target(old_prefix, m['path']) }
           next if targets.any?(&:nil?) || targets.uniq.size != 1

           { 'from' => old_prefix, 'to' => targets.first, 'resolves' => entries.size }
         end
  end

  # A grouped, editor-friendly sentence for the export pre-flight failure. The
  # caller appends the verify_media/relink pointer (it knows the library name).
  def problem_summary(total:)
    bad = problems.size
    clause = bad == 1 ? "source file isn't where the library expects it" : "source files aren't where the library expects them"
    msg = +"#{bad} of #{total} #{clause}."

    prefixes = problems.map { |m| volume_prefix(m['path']) }.uniq
    msg << " They're all under #{prefixes.first}/ — is that drive plugged in, or has it been renamed?" if prefixes.size == 1 && prefixes.first

    unless phantom_volumes.empty?
      verb = phantom_volumes.size == 1 ? 'is a leftover folder' : 'are leftover folders'
      msg << " Note: #{phantom_volumes.join(', ')} #{verb} on this Mac's internal disk, not the real drive."
    end
    msg
  end

  private

  def count(status) = media.count { |m| m['status'] == status }

  def status_of(path)
    return 'missing' unless File.exist?(path)
    return 'phantom' if phantom?(path)

    'ok'
  end

  def phantom?(path)
    vol = volume_prefix(path)
    return false unless vol

    # Cached per volume — a library's clips overwhelmingly share one drive, so
    # this is 3 syscalls per volume instead of per file.
    @squatter ||= Hash.new { |cache, v| cache[v] = squatter_folder?(v) }
    @squatter[vol]
  end

  # Phantom = the volume root `/Volumes/<X>` is a real (non-symlink) dir on the boot
  # device — a leftover mount folder, not the drive (a symlinked root reads ok).
  def squatter_folder?(vol)
    return false if File.symlink?(vol)
    return false unless File.directory?(vol)

    File.stat(vol).dev == @root_dev
  rescue SystemCallError
    false
  end

  # `/Volumes/<X>` for a path under volumes_root, else nil.
  def volume_prefix(path)
    return nil unless under_volumes?(path)

    name = path.delete_prefix("#{@volumes_root}/").split('/').first
    return nil if name.nil? || name.empty?

    File.join(@volumes_root, name)
  end

  def under_volumes?(path) = path.to_s.start_with?("#{@volumes_root}/")

  # The single other mounted volume holding this file's tail (its remap target),
  # or nil when zero or >1 match. Symlinked, non-dir, and boot-device volumes
  # are skipped upstream.
  def remap_target(old_prefix, path)
    tail = path.delete_prefix("#{old_prefix}/")
    return nil if tail == path # not actually under old_prefix

    hits = mounted_volumes.reject { |vol| vol == old_prefix }
                          .select { |vol| File.exist?(File.join(vol, tail)) }
    hits.size == 1 ? hits.first : nil
  end

  # Real mounts only: a `/Volumes` entry on the boot device is another leftover
  # squatter folder — a copy found inside one must never become a relink target.
  # One unreadable entry (a stale network mount, say) is skipped on its own —
  # it must not wipe out every other volume's suggestion.
  def mounted_volumes
    @mounted_volumes ||= volumes_entries.filter_map do |name|
      vol = File.join(@volumes_root, name)
      vol if real_mount?(vol)
    end
  end

  def volumes_entries
    Dir.children(@volumes_root)
  rescue SystemCallError
    []
  end

  def real_mount?(vol)
    return false if File.symlink?(vol) || !File.directory?(vol)

    File.stat(vol).dev != @root_dev
  rescue SystemCallError
    false
  end

  # A missing volumes_root (non-Mac test envs) falls back to `/` — no path can
  # sit under it anyway, so phantom detection is inert there.
  def device_of(dir)
    File.stat(dir).dev
  rescue SystemCallError
    File.stat('/').dev
  end
end
