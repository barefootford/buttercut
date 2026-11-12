require 'spec_helper'
require 'tempfile'

# ButterCut's version is never bumped by hand: it's the newest month heading in
# CHANGELOG.md. Pin how that heading is read.
RSpec.describe ButterCut do
  def changelog(text)
    file = Tempfile.new(['CHANGELOG', '.md'])
    file.write(text)
    file.close
    file.path
  end

  describe '.newest_release' do
    it 'reads the first month heading' do
      path = changelog("# Changelog\n\nIntro.\n\n## November 2026\n\n- A change.\n\n## October 2026\n")

      expect(ButterCut.newest_release(path)).to eq(['November', 2026])
    end

    it 'reads the month from a dated heading, which older releases carry' do
      expect(ButterCut.newest_release(changelog("## August 9, 2026\n"))).to eq(['August', 2026])
    end

    it 'skips headings that name no month' do
      path = changelog("## Coming soon\n\n### November 2026 ideas\n\n## March 2027\n")

      expect(ButterCut.newest_release(path)).to eq(['March', 2027])
    end

    it 'is nil when there is no changelog or no month in it' do
      expect(ButterCut.newest_release('/nonexistent/CHANGELOG.md')).to be_nil
      expect(ButterCut.newest_release(changelog("# Changelog\n"))).to be_nil
    end
  end

  it 'derives VERSION and RELEASE from the changelog this checkout ships' do
    month, year = ButterCut.newest_release

    expect(ButterCut::RELEASE).to eq("#{month} #{year}")
    expect(ButterCut::VERSION).to eq(format('%d.%02d', year, ButterCut::MONTHS.index(month) + 1))
    expect(ButterCut::VERSION).to match(/\A\d{4}\.\d{2}\z/)
  end
end
