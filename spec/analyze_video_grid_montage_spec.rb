require_relative 'spec_helper'
require_relative '../skills/analyze-video/grid_montage'

RSpec.describe GridMontage do
  describe '.layout_for_duration' do
    it 'uses fewer tiles for short clips and a full grid for longer clips' do
      expectations = {
        5 => [3, 1, 3],
        10 => [2, 2, 4],
        30 => [3, 2, 6],
        60 => [4, 2, 8],
        120 => [4, 3, 12],
        121 => [4, 4, 16],
      }

      expectations.each do |duration, expected|
        layout = described_class.layout_for_duration(duration)

        expect([layout.columns, layout.rows, layout.tiles]).to eq(expected)
      end
    end
  end

  describe 'sampling' do
    it 'honors a fixed square grid override' do
      montage = described_class.new(
        video_path: 'video.mov',
        output_path: 'grid.jpg',
        grid: 4,
        tile_w: described_class::DEFAULT_TILE_W,
        tile_h: described_class::DEFAULT_TILE_H,
      )

      layout = montage.send(:layout_for, 0, 5)

      expect([layout.columns, layout.rows, layout.tiles]).to eq([4, 4, 16])
    end

    it 'keeps adaptive seek times inside the decodable range' do
      montage = described_class.new(
        video_path: 'video.mov',
        output_path: 'grid.jpg',
        grid: nil,
        tile_w: described_class::DEFAULT_TILE_W,
        tile_h: described_class::DEFAULT_TILE_H,
      )

      layout = montage.send(:layout_for, 0, 4)
      times = montage.send(:compute_seek_times, 0, 4, layout.tiles)

      expect(times.size).to eq(3)
      expect(times.last).to be <= 3.5
    end
  end
end
